/*
  14 - Correção da nota 120 (filial 502, série 1) do pedido 14206602 - PRODUÇÃO  -  16/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  ATENÇÃO: rodar HOJE (16/11/2026). A rotina de itens grava a data da nota como "hoje"; o script se recusa a
  rodar em outra data.

  O que aconteceu:
    11:24  nota 117 faturou o item 72257 do pedido 14206602. A SP_FIKON_INTEGRA_MOV_ITSAIDA marcou o item com
           TPPED = 'P' (regra antiga: série '1').
    11:33  nota 117 cancelada. O item voltou para STATUS 5 / QTLIB 1, mas continuou com TPPED = 'P'.
    13:14  nota 120 refaturou o pedido. A rotina de itens só pega TPPED = 'R': gravou o cabeçalho sem itens e
           com VLTOTAL nulo. O pedido ficou STATUS 8.
    Também: a nota 120 é NFC-e (modelo 65 na chave), mas foi gravada como modelo 55 / STATUSNFE 2 por causa da
    série '1' (regra corrigida no script 13).
    Estoque do produto 72257 na filial 502: físico 244 (certo); reserva 0, mas deveria ser 1 (o pedido segue
    em aberto). A nota de entrada do cancelamento somou 1 indevido na reserva, e o cupom 118 tirou 1 indevido.

  O que o script faz (tudo numa transação; se uma conferência falhar, desfaz tudo):
    1. Confere a situação atual: a nota 120 sem itens, o item do pedido com STATUS 5, TPPED 'P' e QTLIB 1, e
       o estoque com físico 244 e reserva 0. Se algo estiver diferente, não altera nada.
    2. Cabeçalho da nota 120: MODELONF 65 e STATUSNFE 3 (NFC-e, pela chave de acesso).
    3. Reserva do produto 72257 na filial 502: +1 (fica 1, a reserva do pedido em aberto), com registro no
       extrato de estoque.
    4. Item do pedido: TPPED 'P' -> 'R'.
    5. Executa a própria SP_FIKON_INTEGRA_MOV_ITSAIDA para a nota 120, com os mesmos parâmetros do fluxo
       normal. Ela grava o item, baixa o estoque (físico 243, reserva 0), grava o VLTOTAL e marca o pedido
       como faturado (STATUS 6).
    6. Confere o resultado: 1 item na nota, VLTOTAL 2,00, pedido STATUS 6, item STATUS 6, físico 243 e
       reserva 0. Só então faz o COMMIT.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
  O resultado aparece nas consultas "ANTES" e "DEPOIS" e na mensagem final.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @codfil int = 502, @numnota numeric(12,0) = 120, @serie varchar(3) = '1', @dtnota date = '2026-11-16',
        @numpedven numeric(12,0) = 14206602, @coditprod numeric(10,0) = 72257, @codcli numeric(12,0) = 137377,
        @hrhora datetime = '2026-11-16 13:14:11', @estado varchar(2) = 'CE',
        @chave varchar(44) = '23261107201916001716650010000001201073778518';
DECLARE @erro varchar(1000) = '';
DECLARE @fisico numeric(9,3), @resfis numeric(9,3);

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, s.NUMNOTA, s.SERIE, s.MODELONF, s.STATUSNFE, s.VLTOTAL,
       (SELECT COUNT(*) FROM MOV_ITSAIDA i WHERE i.CODFIL = s.CODFIL AND i.TPNOTA = s.TPNOTA AND i.NUMNOTA = s.NUMNOTA AND i.SERIE = s.SERIE AND i.DTNOTA = s.DTNOTA) AS itens_nota,
       (SELECT STATUS FROM MOV_PEDIDO WHERE NUMPEDVEN = @numpedven AND CODFIL = @codfil AND TIPOPED = 0) AS status_pedido,
       it.STATUS AS status_item, it.TPPED, it.QTLIB, it.QTFAT, pl.FISICO, pl.RESFIS
  FROM MOV_SAIDA s
  CROSS JOIN (SELECT STATUS, TPPED, QTLIB, QTFAT FROM MOV_ITPED WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven AND CODITPROD = @coditprod AND ITEM = 1) it
  CROSS JOIN (SELECT FISICO, RESFIS FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod) pl
 WHERE s.CODFIL = @codfil AND s.NUMNOTA = @numnota AND s.SERIE = @serie AND s.DTNOTA = @dtnota AND s.NUMPEDVEN = @numpedven;

-- ===================== 1. Conferências =====================
IF CAST(GETDATE() AS date) <> @dtnota
    SET @erro = @erro + 'O script so pode rodar em 16/11/2026 (a rotina de itens grava a data de hoje). ';

IF NOT EXISTS (SELECT 1 FROM MOV_SAIDA WHERE CODFIL = @codfil AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota
                  AND NUMPEDVEN = @numpedven AND CHAVENFE = @chave AND STATUS <> 9 AND DTCANCEL IS NULL)
    SET @erro = @erro + 'Nota 120 nao encontrada ativa com a chave esperada. ';

IF EXISTS (SELECT 1 FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota)
    SET @erro = @erro + 'A nota 120 ja tem itens (ja corrigida?). ';

IF NOT EXISTS (SELECT 1 FROM MOV_ITPED WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven AND CODITPROD = @coditprod
                  AND ITEM = 1 AND STATUS = 5 AND TPPED = 'P' AND FLLIBFAT = 'S' AND QTLIB = 1 AND QTFAT = 0 AND FILORIG = @codfil)
    SET @erro = @erro + 'Item do pedido 14206602 fora da situacao esperada (STATUS 5, TPPED P, QTLIB 1). ';

IF (SELECT COUNT(*) FROM MOV_ITPED WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven) <> 1
    SET @erro = @erro + 'O pedido 14206602 deveria ter 1 item. ';

SELECT @fisico = FISICO, @resfis = RESFIS FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod;
IF ISNULL(@fisico, -1) <> 244 OR ISNULL(@resfis, -1) <> 0
    SET @erro = @erro + 'Estoque do 72257 na filial 502 mudou (esperado fisico 244 / reserva 0): conferir antes de corrigir. ';

IF OBJECT_ID('dbo.FN_FIKON_MODELO_NF') IS NULL
    SET @erro = @erro + 'Funcao dbo.FN_FIKON_MODELO_NF nao existe (rodar o script 13b). ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2 a 6. Correção =====================
BEGIN TRY
    BEGIN TRAN;

    -- 2. Cabeçalho: NFC-e (modelo 65 na chave de acesso)
    UPDATE MOV_SAIDA SET MODELONF = '65', STATUSNFE = 3
     WHERE CODFIL = @codfil AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota AND NUMPEDVEN = @numpedven;

    -- 3. Reserva do pedido em aberto: +1 (físico não muda), com registro no extrato
    EXEC SPU_PROLOCI 1, @codfil, 'L', @coditprod, 0, 1, 0, 0, 0, 0, 0, 0, 0, NULL, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0;

    INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD, FISICO, RESFIS, ENCOMENDA, FUTURO,
                                 LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS,
                                 RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS,
                                 CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC)
    VALUES (@codfil, @numpedven, @numnota, GETDATE(), 251, 'S', 3, @coditprod, @fisico, @resfis, 0, 0,
            0, 0, 0, 0, 0, 1, 'RESFIS;', 'N', @fisico,
            @resfis + 1, 0, 0, 0, 0, 0, 0, 0,
            @codfil, GETDATE(), 'AJUSTE RESERVA', '{CALL SPU_PROLOCI(1, 502, L, 72257, 0, 1, ...)} script 14: reserva do pedido 14206602 (cancelamento da nota 117)',
            'CORRECAO SCRIPT 14');

    -- 4. Item do pedido volta a ser faturável pela rotina
    UPDATE MOV_ITPED SET TPPED = 'R'
     WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven AND CODITPROD = @coditprod AND ITEM = 1 AND TPPED = 'P';

    -- 5. Grava os itens da nota 120 pela rotina normal do faturamento
    EXEC dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA @numpedven, @numnota, @serie, @codfil, @codcli, @hrhora, @estado;

    -- 6. Conferência do resultado
    SET @erro = '';

    IF (SELECT COUNT(*) FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota) <> 1
        SET @erro = @erro + 'A nota 120 nao ficou com 1 item. ';

    IF ISNULL((SELECT VLTOTAL FROM MOV_SAIDA WHERE CODFIL = @codfil AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota AND NUMPEDVEN = @numpedven), 0) <> 2
        SET @erro = @erro + 'VLTOTAL da nota 120 diferente de 2,00. ';

    IF (SELECT STATUS FROM MOV_ITPED WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven AND CODITPROD = @coditprod AND ITEM = 1) <> 6
        SET @erro = @erro + 'Item do pedido nao ficou STATUS 6. ';

    IF (SELECT STATUS FROM MOV_PEDIDO WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven) <> 6
        SET @erro = @erro + 'Pedido nao ficou STATUS 6. ';

    IF NOT EXISTS (SELECT 1 FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod AND FISICO = 243 AND RESFIS = 0)
        SET @erro = @erro + 'Estoque do 72257 nao ficou fisico 243 / reserva 0. ';

    IF @erro <> ''
    BEGIN
        RAISERROR('Conferencia final falhou, tudo foi desfeito: %s', 16, 1, @erro);
    END

    COMMIT;
    PRINT 'Correcao aplicada: nota 120 com o item, pedido 14206602 faturado, estoque conferido.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, s.NUMNOTA, s.SERIE, s.MODELONF, s.STATUSNFE, s.VLTOTAL,
       (SELECT COUNT(*) FROM MOV_ITSAIDA i WHERE i.CODFIL = s.CODFIL AND i.TPNOTA = s.TPNOTA AND i.NUMNOTA = s.NUMNOTA AND i.SERIE = s.SERIE AND i.DTNOTA = s.DTNOTA) AS itens_nota,
       (SELECT STATUS FROM MOV_PEDIDO WHERE NUMPEDVEN = @numpedven AND CODFIL = @codfil AND TIPOPED = 0) AS status_pedido,
       it.STATUS AS status_item, it.TPPED, it.QTLIB, it.QTFAT, pl.FISICO, pl.RESFIS
  FROM MOV_SAIDA s
  CROSS JOIN (SELECT STATUS, TPPED, QTLIB, QTFAT FROM MOV_ITPED WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven AND CODITPROD = @coditprod AND ITEM = 1) it
  CROSS JOIN (SELECT FISICO, RESFIS FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod) pl
 WHERE s.CODFIL = @codfil AND s.NUMNOTA = @numnota AND s.SERIE = @serie AND s.DTNOTA = @dtnota AND s.NUMPEDVEN = @numpedven;

SELECT 'ITEM GRAVADO' AS momento, i.ITEM, i.CODITPROD, i.QTCOMP, i.PRECOUNIT, i.VLTOTAL, i.CTF, i.CODVENDR, i.CODNATOP
  FROM MOV_ITSAIDA i
 WHERE i.CODFIL = @codfil AND i.NUMNOTA = @numnota AND i.SERIE = @serie AND i.DTNOTA = @dtnota;
