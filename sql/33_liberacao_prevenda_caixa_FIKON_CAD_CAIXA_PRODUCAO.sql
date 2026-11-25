/*
  33 - Liberação de pré-venda FIKON: caixa/operador pela FIKON_CAD_CAIXA - PRODUÇÃO  -  24/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  (O DEV não estava acessível ao gerar este script; a versão do DEV será conferida à parte.)
  IMPORTANTE: rodar ANTES de publicar o Integrador que passa a enviar a série.

  Problema:
    A SP_FIKON_ATUALIZA_STATUS_PEDIDO (pedido do app que passou no caixa da FIKON) gravava os lançamentos da
    CXA_LANCTO sempre no caixa/operador "CARTOES" da filial (DM: caixa 6 PDVDM_CARTOES, operador 19), sem olhar
    a FIKON_CAD_CAIXA (DM: série U05 -> caixa 4, série U06 -> caixa 3, operador 24 PDVFIKON).

  O que muda (procedure completa abaixo):
    1. Novo parâmetro opcional @serie (série da nota no Gemco, ex.: U05). Quem chama sem ele continua funcionando.
    2. Caixa e operador vêm da FIKON_CAD_CAIXA da filial: a linha da série, se informada; senão a primeira linha
       da filial (menor ID).
    3. Só se a filial NÃO tem nenhuma linha na FIKON_CAD_CAIXA usa o caixa/operador "CARTOES" (como antes).
       Ex.: filial 502 continua no PDVARAC_CARTOES.
    Nada mais muda (status 5, taxas, convênio, NUMMOV 1, fila FIKON_INTEGRACAO_PEDIDO).

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
    - O bloco 1 confere a versão da procedure (SHA-256 CFB60F6F...) e guarda a cópia
      SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_SCRIPT33. Se algo estiver diferente, nada é alterado.
  Para voltar atrás: abrir a cópia _BKP_SCRIPT33, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO'));

IF @def IS NULL
   OR (HASHBYTES('SHA2_256', @def) <> 0xCFB60F6F27667A5FAAEE917F8B628E1839AA0661D59104C8FBDAF1E40EE0D58B AND CHARINDEX(N'script 33', @def) = 0)
BEGIN
    RAISERROR('Nada foi alterado: SP_FIKON_ATUALIZA_STATUS_PEDIDO nao existe ou esta numa versao diferente da esperada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_SCRIPT33') IS NULL
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_ATUALIZA_STATUS_PEDIDO]', N'[dbo].[SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_SCRIPT33]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_SCRIPT33') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copia guardada: SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_SCRIPT33.';
END
GO

/* ===================== 2. SP_FIKON_ATUALIZA_STATUS_PEDIDO (completa) ===================== */
ALTER PROC [dbo].[SP_FIKON_ATUALIZA_STATUS_PEDIDO]  

-- TIPO
-- D Debito
-- C Credito
-- P Pix Maquina Rede
-- F Pix FixPay

@NUMPEDVEN NUMERIC(12,0),
@CODFIL int,
@documento varchar(20),
@bandeira varchar(20),
@tipo varchar(1),
@serie varchar(3) = NULL   -- script 33: serie da nota no Gemco (ex.: U05), quando o Integrador ja souber

AS

-- script 33 (24/11/2026): caixa e operador do lancamento pela dbgemco.dbo.FIKON_CAD_CAIXA (filial + serie; sem serie
-- ou sem linha da serie, a primeira linha da filial). Caixa/operador 'CARTOES' so quando a filial nao tem nenhuma
-- linha na FIKON_CAD_CAIXA (comportamento anterior).

DECLARE @coditprod numeric(9,0)
DECLARE @filorig int
DECLARE @qtcomp numeric(9,4)
DECLARE @tpdepos varchar(1) ='N'
DECLARE @tpdepostransf varchar(1) ='N'
DECLARE @codfiltransf int
DECLARE @fllotevencto varchar(1)
DECLARE @lote varchar(20)
DECLARE @encomenda varchar(1)
DECLARE @numpedtransf numeric(9,0)
DECLARE @coduser numeric(9,0) = 508
DECLARE @codoper int
DECLARE @numcxa int
DECLARE @taxadm numeric(9,2)
DECLARE @codcon int
DECLARE @qtprc int


-- script 33: caixa/operador da FIKON_CAD_CAIXA (a linha da serie primeiro; senao a primeira da filial)
SELECT TOP (1) @numcxa = c.CAIXA, @codoper = c.CODOPER
  FROM dbgemco.dbo.FIKON_CAD_CAIXA c
 WHERE c.CODFIL = @CODFIL AND c.CAIXA IS NOT NULL AND c.CODOPER IS NOT NULL
 ORDER BY CASE WHEN @serie IS NOT NULL AND c.SERIE = LTRIM(RTRIM(@serie)) THEN 0 ELSE 1 END, c.ID

-- filial sem nenhuma linha na FIKON_CAD_CAIXA: caixa/operador 'CARTOES' (como antes)
IF @numcxa IS NULL
BEGIN
    SET @numcxa = (SELECT NUMCXA FROM dbgemco..CXA_CAIXAS WHERE CODFIL=@CODFIL AND DESCXA LIKE '%CARTOES')

    SET @codoper = (SELECT CODOPER FROM dbgemco..CXA_OPERADOR WHERE CODFIL=@CODFIL AND NOME LIKE '%CARTOES')
END


IF(@documento = '')
    SET @documento = null


DECLARE CR_UPDATE CURSOR FOR
SELECT itp.coditprod, itp.FILORIG, itp.qtcomp*-1, itp.tpdepos, itp.CODFILTRANSF, isnull(FLLOTEVENCTO,'N'), isnull(FLVDANTEC,'N'), itf.numpedtransf 
FROM dbgemco..mov_itped itp 
LEFT JOIN dbgemco..mov_itpedtransf itf on itp.numpedven=itf.numpedven and itp.coditprod=itf.CODITPROD and itp.codfiltransf=itf.CODFILTRANSF and isnull(itf.status,0)<9
WHERE itp.NUMPEDVEN=@NUMPEDVEN
GROUP BY itp.coditprod, itp.FILORIG, itp.qtcomp*-1, itp.tpdepos, itp.CODFILTRANSF, isnull(FLLOTEVENCTO,'N'), isnull(FLVDANTEC,'N'), itf.numpedtransf

OPEN CR_UPDATE
FETCH NEXT FROM CR_UPDATE INTO @coditprod, @filorig, @qtcomp, @tpdepos, @codfiltransf, @fllotevencto, @encomenda, @numpedtransf
WHILE @@FETCH_STATUS = 0
BEGIN

    UPDATE dbgemco..mov_pedido SET fllibfat='S' WHERE NUMPEDVEN=@numpedtransf
    UPDATE dbgemco..mov_itped SET fllibfat='S' WHERE NUMPEDVEN=@numpedtransf

    FETCH NEXT FROM CR_UPDATE INTO @coditprod, @filorig, @qtcomp, @tpdepos, @codfiltransf, @fllotevencto, @encomenda, @numpedtransf
END

CLOSE CR_UPDATE
DEALLOCATE CR_UPDATE 

-- Busca quantidade de parcelas com segurança
SET @qtprc = (SELECT max(numprc) FROM dbgemco..cxa_lancto WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN)
SET @qtprc = ISNULL(@qtprc, 1)

IF(@tipo='D')
BEGIN
    -- Correção no ON: Usa TRY_CAST para evitar erro caso c.codcon seja varchar com lixo/vazio
    SET @taxadm = (SELECT isnull(max(g.TAXADM),2.3) FROM dbgemco..CXA_CADCON(nolock) g INNER JOIN dbaplicativos..CASH_CONVENIADAS (nolock) c on g.codcon = TRY_CAST(c.codcon AS int) WHERE CAST(c.bandeira AS varchar(20)) = @bandeira and c.tipo=@tipo )
END
ELSE
BEGIN
    -- Correção no ON: Mesmo tratamento para vendas a prazo/crédito
    SET @taxadm = (SELECT isnull(max(g.TAXADM),2.3) FROM dbgemco..CXA_CADCON_PRAZO(nolock) g INNER JOIN dbaplicativos..CASH_CONVENIADAS (nolock) c on g.codcon = TRY_CAST(c.codcon AS int) WHERE CAST(c.bandeira AS varchar(20)) = @bandeira AND g.PRACON=@qtprc and c.tipo=@tipo )
END

-- Busca o código do convênio convertendo com segurança se necessário
SET @codcon = (SELECT isnull(max(TRY_CAST(codcon AS int)),1) FROM dbaplicativos..CASH_CONVENIADAS(nolock) WHERE CAST(BANDEIRA AS varchar(20)) = @bandeira and tipo = @tipo )


IF(@tipo='P')
BEGIN
    UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2, NUMDOC = @documento, TAXADM=0.95, CODPORT = 52, CODCON=49, forma='139', codeve=139 WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN and codeve=139
END

IF(@tipo='F')
BEGIN
    UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2, NUMDOC = @documento, TAXADM=1.19, CODPORT = 59, CODCON=327, forma='142', codeve=142 WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN
END


IF(@tipo not in ('P','F'))  
BEGIN
   if(select min(codeve) from cxa_lancto where TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN ) not in (5, 145)
   begin
    UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2, NUMDOC = @documento, TAXADM=@taxadm, CODCON=@codcon WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN and codeve not in (139)
	end
	  else
	     begin
		   UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
           UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
           UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2  WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN and codeve not in (139)
		 end
END


-----------------------------------------------------------------------------------------
--  Atualiza a tabela de controle Fikon/Gemco
-----------------------------------------------------------------------------------------
UPDATE [dbgemco].[dbo].[FIKON_INTEGRACAO_PEDIDO]
SET [STATUS] = 'LIBERADO CXA'
WHERE [pedido_gemco] = @NUMPEDVEN
GO

SET NOEXEC OFF;
GO

SELECT o.name, o.modify_date,
       CASE WHEN o.name = 'SP_FIKON_ATUALIZA_STATUS_PEDIDO'
            THEN CASE WHEN CHARINDEX('script 33', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script33
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_ATUALIZA_STATUS_PEDIDO', 'SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_SCRIPT33')
 ORDER BY o.name;

-- caixa/operador que cada filial vai usar (FIKON_CAD_CAIXA, ou CARTOES quando a filial nao esta na tabela)
SELECT c.CODFIL, c.SERIE, c.CAIXA, c.CODOPER, cx.DESCXA, op.NOME AS operador
  FROM FIKON_CAD_CAIXA c
  LEFT JOIN CXA_CAIXAS cx ON cx.CODFIL = c.CODFIL AND cx.NUMCXA = c.CAIXA
  LEFT JOIN CXA_OPERADOR op ON op.CODFIL = c.CODFIL AND op.CODOPER = c.CODOPER
 ORDER BY c.CODFIL, c.ID;
GO
