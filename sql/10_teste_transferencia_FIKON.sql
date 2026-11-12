/*
  TESTE das procedures do script 10 (transferência FIKON -> Gemco)  -  11/11/2026
  Rodar SÓ no DEV (10.1.5.226, dbgemco), no SSMS, o script INTEIRO (F5).

  Tudo roda dentro de uma transação que termina SEMPRE em ROLLBACK: nada fica gravado
  (nem o número do pedido na SEQPED). Durante a execução, as tabelas tocadas ficam travadas
  por alguns segundos.

  Cenário (mesmas chamadas que o ApiAcal faz):
    Origem: estabelecimento FIKON 278423 (filial 1) -> destino 278435 (filial 5)
    Nota fictícia: número 999999001, série 1, chave 99000...999999001
    Itens:
      94020 (CTF 0)   qtd 2  x 17,51 = 35,02
      67408 (CTF 60)  qtd 3  x 11,25 = 33,75
      77851 (CTF 20)  qtd 2  x 23,74 = 47,48
      88774 (lote)    qtd 3  x 30,00 = 90,00   lote 250014 (saldo 3 -> o lote zera e deve ser apagado)
    Total: 206,25

  O que conferir no resultado:
    1. Pedido (MOV_PEDIDO/MOV_ITPED) na filial 1, CODCLI 5, STATUS 6, totais = 206,25.
    2. Nota (MOV_SAIDA) STATUS 2 / STATUSNFE 2, natureza 515/2 + 540/9, totais fiscais.
    3. Itens (MOV_ITSAIDA): ICMS por CTF (0: base = total; 20: base reduzida; 60: em outras).
    4. Estoque: origem FISICO -q (RESFIS igual ao de antes); destino TRANSITO +q.
    5. Lote: MOV_LOTEVENCTO_NF com STATUS 6 e QTDE 3; lote 250014 apagado da MOV_LOTEVENCTO.
    6. Fila de NF-e do Gemco: nenhuma linha na INT_NFE_SAIDA / FIS_NFE_INTEGRACAO para a nota.
    7. Extrato (MOV_EXTRATOPROD): 3 linhas por item (pedido: TRANSITO e RESFIS; nota: FISICO;RESFIS).
*/
SET NOCOUNT ON;

DECLARE @chave      varchar(44)   = '99' + REPLICATE('0', 33) + '999999001'
DECLARE @numnota    numeric(9,0)  = 999999001
DECLARE @serie      varchar(3)    = '1'
DECLARE @dtemissao  datetime      = GETDATE()
DECLARE @origem     numeric(15,0) = 278423     -- filial 1
DECLARE @destino    numeric(15,0) = 278435     -- filial 5
DECLARE @erro       nvarchar(2000)

-- Itens do teste (código FIKON = CODITPROD + dígito, montado pela CAD_ITPROD)
DECLARE @itens TABLE (ORDEM int, CODITPROD numeric(10,0), CODIGO varchar(20), QTCOMP numeric(9,3),
                      PRECOUNIT numeric(17,4), VLTOTAL numeric(15,2), LOTES varchar(4000))

INSERT INTO @itens (ORDEM, CODITPROD, QTCOMP, PRECOUNIT, VLTOTAL, LOTES)
VALUES (1, 94020, 2, 17.51, 35.02, NULL),
       (2, 67408, 3, 11.25, 33.75, NULL),
       (3, 77851, 2, 23.74, 47.48, NULL),
       (4, 88774, 3, 30.00, 90.00, '250014:3')

UPDATE i SET CODIGO = CONVERT(varchar(12), ip.CODITPROD) + CONVERT(varchar(2), ip.DIGITPROD)
  FROM @itens i JOIN dbo.CAD_ITPROD ip ON ip.CODITPROD = i.CODITPROD

IF EXISTS (SELECT 1 FROM @itens WHERE CODIGO IS NULL)
BEGIN
    RAISERROR('Teste: produto de teste nao encontrado na CAD_ITPROD.', 16, 1);
    RETURN;
END

IF EXISTS (SELECT 1 FROM dbo.MOV_SAIDA WHERE CHAVENFE = @chave)
BEGIN
    RAISERROR('Teste: a chave ficticia ja existe na MOV_SAIDA. Troque o numero da nota no teste.', 16, 1);
    RETURN;
END

DECLARE @vltotal numeric(15,2) = (SELECT SUM(VLTOTAL) FROM @itens)

-- Estoque e lote ANTES
IF OBJECT_ID('tempdb..#antes') IS NOT NULL DROP TABLE #antes
SELECT pl.CODFIL, pl.TPDEPOS, pl.CODITPROD, pl.FISICO, pl.RESFIS, pl.TRANSITO
  INTO #antes
  FROM dbo.CAD_PRODLOC pl
 WHERE pl.CODFIL IN (1, 5) AND pl.CODITPROD IN (SELECT CODITPROD FROM @itens)

IF OBJECT_ID('tempdb..#lote_antes') IS NOT NULL DROP TABLE #lote_antes
SELECT CODFIL, CODITPROD, LOTEVENCTO, QTDE, RESFIS, BLOQUEADO
  INTO #lote_antes
  FROM dbo.MOV_LOTEVENCTO
 WHERE CODFIL = 1 AND CODITPROD = 88774 AND LOTEVENCTO = '250014'

DECLARE @seqped_antes numeric(12,0) = (SELECT MAX(LAST_NUMBER) FROM dbo.SEQPED)

BEGIN TRAN

BEGIN TRY
    /* ---------- 1. Pedido e cabeçalho da nota ---------- */
    EXEC dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA
         @numnota = @numnota, @serie = @serie, @chave = @chave, @dtemissao = @dtemissao,
         @vltotal = @vltotal, @estabelecimento = @origem, @estabelecimento_destino = @destino,
         @chcriacao = 'TESTE', @obs = 'TESTE TRANSFERENCIA FIKON (ROLLBACK)'

    /* ---------- 2. Itens ---------- */
    DECLARE @ordem int = 1, @codigo varchar(20), @qt numeric(9,3), @preco numeric(17,4), @tot numeric(15,2), @lotes varchar(4000)

    WHILE @ordem <= (SELECT MAX(ORDEM) FROM @itens)
    BEGIN
        SELECT @codigo = CODIGO, @qt = QTCOMP, @preco = PRECOUNIT, @tot = VLTOTAL, @lotes = LOTES
          FROM @itens WHERE ORDEM = @ordem

        EXEC dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA
             @chavenfe = @chave, @codigo = @codigo, @qtcomp = @qt, @precounit = @preco,
             @vltotal = @tot, @lotes = @lotes

        SET @ordem = @ordem + 1
    END

    /* ---------- 3. Resultado (dentro da transação) ---------- */
    DECLARE @codfil numeric(5,0), @numpedven numeric(12,0), @dtnota datetime
    SELECT @codfil = CODFIL, @numpedven = NUMPEDVEN, @dtnota = DTNOTA FROM dbo.MOV_SAIDA WHERE CHAVENFE = @chave

    SELECT '1. PEDIDO' etapa, CODFIL, TIPOPED, NUMPEDVEN, TPPED, FILORIG, CODCLI, STATUS, SITCARGA, TPNOTA, LOCAL, PRACA,
           VLMERCAD, VLTOTAL, VLVDVISTA, VLTOTITEMACUM, DTPEDIDO, DTENTREGA, OBS
      FROM dbo.MOV_PEDIDO WHERE CODFIL = @codfil AND TIPOPED = 2 AND NUMPEDVEN = @numpedven

    SELECT '1. ITENS DO PEDIDO' etapa, ITEM, CODITPROD, QTCOMP, QTORIG, QTFAT, QTEMITIDO, QTLIB, STATUS, NUMNOTA, PRECOUNIT,
           VLTOTITEM, CTF, TPDEPOS, LOCAL, CMUP, CUE, FLLOTEVENCTO, FLATUTRAN
      FROM dbo.MOV_ITPED WHERE CODFIL = @codfil AND TIPOPED = 2 AND NUMPEDVEN = @numpedven ORDER BY ITEM

    SELECT '2. NOTA' etapa, CODFIL, TPNOTA, NUMNOTA, SERIE, DTNOTA, NUMPEDVEN, FILPED, CODCLI, STATUS, STATUSNFE, MODELONF,
           VLMERCAD, VLTOTAL, VLBASEICMS, VLICM, VLOUTRAS, VLISENTO, PESO, LOCAL, PRACA,
           CODNATOP, CODNATOPCOMPL, CODNATOPDIF, CODNATOPDIFCOMPL, VLBASECBS, VLCBS, VLBASEIBS, VLIBS, CHAVENFE
      FROM dbo.MOV_SAIDA WHERE CHAVENFE = @chave

    SELECT '3. ITENS DA NOTA' etapa, ITEM, CODITPROD, QTCOMP, PRECOUNIT, VLTOTAL, CTF, ALIQICM, ALIQICMRED, ALIQICMSUB,
           VLBASEICMS, VLICM, VLNTRIBUT, VLISENTO, VLOUTRAS, VLBASEICMSF, VLICMF, VLOUTRASF, VLICMOPERSTF,
           CODNATOP, CODNATOPCOMPL, CSTPIS, CSTCOFINS, VLPPIS, VLPCONTSOC, VLBASECBS, VLCBS, VLBASEIBS, VLIBS,
           CMUP, CUE, QTESTOQUE, TPDEPOS, LOCAL, FLLOTEVENCTO, FLATUTRAN, STATUS
      FROM dbo.MOV_ITSAIDA
     WHERE CODFIL = @codfil AND TPNOTA = 144 AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota
     ORDER BY ITEM

    SELECT '4. ESTOQUE' etapa, a.CODFIL, a.TPDEPOS, a.CODITPROD,
           a.FISICO fisico_antes, d.FISICO fisico_depois, d.FISICO - a.FISICO dif_fisico,
           a.RESFIS resfis_antes, d.RESFIS resfis_depois, ISNULL(d.RESFIS, 0) - ISNULL(a.RESFIS, 0) dif_resfis,
           a.TRANSITO transito_antes, d.TRANSITO transito_depois, ISNULL(d.TRANSITO, 0) - ISNULL(a.TRANSITO, 0) dif_transito
      FROM #antes a
      JOIN dbo.CAD_PRODLOC d ON d.CODFIL = a.CODFIL AND d.TPDEPOS = a.TPDEPOS AND d.CODITPROD = a.CODITPROD
     ORDER BY a.CODITPROD, a.CODFIL, a.TPDEPOS

    SELECT '5. LOTE NA NOTA' etapa, CODFIL, TPNOTA, NUMNOTA, SERIE, NUMPEDVEN, CODITPROD, LOTEVENCTO, QTDE, RESFIS, STATUS,
           QTLIB, QTORIG, QTESTOQUE, ITPEDITEM, FILPED, TIPOPED
      FROM dbo.MOV_LOTEVENCTO_NF WHERE NUMPEDVEN = @numpedven AND TIPOPED = 2 AND TPNOTA = 144

    SELECT '5. LOTE NO ESTOQUE' etapa, a.LOTEVENCTO, a.QTDE qtde_antes, a.RESFIS resfis_antes,
           lv.QTDE qtde_depois, lv.RESFIS resfis_depois,
           CASE WHEN lv.LOTEVENCTO IS NULL THEN 'APAGADO (zerou)' ELSE 'ainda existe' END situacao
      FROM #lote_antes a
      LEFT JOIN dbo.MOV_LOTEVENCTO lv ON lv.CODFIL = a.CODFIL AND lv.CODITPROD = a.CODITPROD AND lv.LOTEVENCTO = a.LOTEVENCTO

    SELECT '6. FILA NF-e (tem de ser 0)' etapa,
           (SELECT COUNT(*) FROM dbo.INT_NFE_SAIDA WHERE CODFIL = @codfil AND TPNOTA = 144 AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota) int_nfe_saida,
           (SELECT COUNT(*) FROM dbo.FIS_NFE_INTEGRACAO WHERE TipoMovimento = 1 AND Serie = @serie AND Numero = @numnota AND DataEmissao = @dtnota) fis_nfe_integracao

    SELECT '7. EXTRATO' etapa, CODFIL, NUMPED, NUMNOTA, TPNOTA, MODULO, CODITPROD, QTDEATUALIZADO, CAMPOSATUALIZADO,
           FISICO, FISICOPOS, RESFIS, RESFISPOS, TRANSITO, TRANSITOPOS, ROTINA
      FROM dbo.MOV_EXTRATOPROD WHERE NUMPED = @numpedven ORDER BY CODITPROD, DATAHORAID, CODFIL

    SELECT 'SEQPED' etapa, @seqped_antes antes, (SELECT MAX(LAST_NUMBER) FROM dbo.SEQPED) durante_teste
END TRY
BEGIN CATCH
    SET @erro = 'ERRO NO TESTE: ' + ERROR_MESSAGE() + ' (proc ' + ISNULL(ERROR_PROCEDURE(), '-')
              + ', linha ' + CONVERT(varchar(10), ERROR_LINE()) + ')'
    SELECT @erro AS resultado
END CATCH

/* ---------- Desfaz tudo ---------- */
IF @@TRANCOUNT > 0 ROLLBACK

SELECT 'ROLLBACK executado: nada foi gravado' AS final,
       (SELECT COUNT(*) FROM dbo.MOV_SAIDA WHERE CHAVENFE = @chave) nota_depois_rollback,
       (SELECT MAX(LAST_NUMBER) FROM dbo.SEQPED) seqped_depois_rollback
