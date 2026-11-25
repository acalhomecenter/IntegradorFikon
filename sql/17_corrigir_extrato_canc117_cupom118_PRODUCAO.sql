/*
  17 - Extrato de produtos: corrige o cancelamento 117 e o cupom 118 (filial 502) - PRODUÇÃO  -  16/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  Problema: na tela Extrato/Movimentação de Produtos (produto 722575, filial 502, 16/11/2026), o cancelamento
  da nota 117 (série CAN) e a venda do cupom 118 aparecem com quantidade 0.
    - ENT_ITENT do cancelamento 117: CONVERSAO, PRECOUNIT, VLTOTAL, VLTOTITEM, VLOUTRAS e VLOUTRASF nulos;
    - MOV_ITSAIDA do cupom 118: QTEMB nulo.
  As procedures já foram corrigidas (script 16); este script acerta só esses dois registros.
  O estoque (CAD_PRODLOC) já está certo e NÃO é alterado.

  Por que o UPDATE é seguro (triggers analisados em 16/11/2026):
    - MOV_ITSAIDA_TR_UPD: o que mexe em estatística (EST_PROD / EST_PRODVEN) só roda se a coluna STATUS for
      alterada (não é); o bloco SMARTECF só roda com TPPROG = 'S' (o item tem NULL) e trata QTEMB nulo como 1;
      FLREPLICA/FLINT nulos, então não há replicação. Sobra só a regravação de FLVALIDAPAFECF.
    - ent_itent_tr_upd: EST_PROD / EST_PRODVEN só com o item cancelado (STATUS 9) e nota de venda; o item
      está com STATUS 1 e o tipo de nota 12 tem TPREM 'N' / FLVENDA 'N'. Sobra regravar CUEORIG e DTATUEST
      com os valores que já existem e marcar/desmarcar os flags de replicação (como em qualquer alteração).

  O que o script faz (numa transação):
    1. Confere que os dois registros estão exatamente nesse estado e que as condições acima continuam
       valendo. Se algo estiver diferente, não altera nada.
    2. ENT_ITENT do cancelamento 117: preço, total e embalagem do item vendido na nota 117 (MOV_ITSAIDA):
       CONVERSAO = QTEMB da venda (1), PRECOUNIT, VLTOTAL, VLTOTITEM, VLOUTRAS = total, VLOUTRASF = unitário.
    3. MOV_ITSAIDA do cupom 118: QTEMB = QTEMB da embalagem 0 do produto (CAD_EMBAL, 1).
    4. Confere o resultado, inclusive que o estoque e a estatística do produto não mudaram, e só então faz o
       COMMIT.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @erro varchar(1000) = '';
DECLARE @coditprod numeric(10,0) = 72257, @codfil int = 502, @dtnota date = '2026-11-16';
DECLARE @precounit numeric(17,4), @vltotal numeric(15,2), @qtcomp numeric(9,3), @qtemb_venda numeric(4,0), @qtemb_cad numeric(4,0);
DECLARE @fisico_antes numeric(9,3), @resfis_antes numeric(9,3), @estprod_antes numeric(20,6), @estprodven_antes numeric(20,6);

-- Dados do item vendido na nota 117 (origem do cancelamento) e embalagem 0 do produto
SELECT @precounit = i.PRECOUNIT, @vltotal = i.VLTOTAL, @qtcomp = i.QTCOMP, @qtemb_venda = ISNULL(NULLIF(i.QTEMB, 0), 1)
  FROM MOV_ITSAIDA i
 WHERE i.CODFIL = @codfil AND i.TPNOTA = 251 AND i.NUMNOTA = 117 AND i.DTNOTA = @dtnota AND i.CODITPROD = @coditprod AND i.ITEM = 1;

SELECT @qtemb_cad = ISNULL(NULLIF(e.QTEMB, 0), 1)
  FROM CAD_EMBAL e JOIN CAD_ITPROD itp ON itp.CODPROD = e.CODPROD
 WHERE itp.CODITPROD = @coditprod AND e.CODEMBAL = 0;

-- Fotografia do estoque e da estatística, para conferir no fim que nada disso mudou
SELECT @fisico_antes = FISICO, @resfis_antes = RESFIS FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod;
SELECT @estprod_antes = SUM(ISNULL(QTVENLIQ, 0)) FROM EST_PROD WHERE CODFIL = @codfil AND CODITPROD = @coditprod AND DTVENDA = @dtnota;
SELECT @estprodven_antes = SUM(ISNULL(QTVENLIQ, 0)) FROM EST_PRODVEN WHERE CODFIL = @codfil AND CODITPROD = @coditprod AND DTVENDA = @dtnota;

-- ===================== ANTES =====================
SELECT 'ANTES - cancelamento 117' AS registro, CONVERSAO, PRECOUNIT, VLTOTAL, VLTOTITEM, VLOUTRAS, VLOUTRASF, QTCOMP, QTESTOQUE, STATUS, CUEORIG, DTATUEST
  FROM ENT_ITENT WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = 117 AND DTNOTA = @dtnota AND CODITPROD = @coditprod;
SELECT 'ANTES - cupom 118' AS registro, QTEMB, CONVERSAO, QTCOMP, QTESTOQUE, STATUS, TPPROG
  FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND TPNOTA = 251 AND NUMNOTA = 118 AND DTNOTA = @dtnota AND CODITPROD = @coditprod;

-- ===================== 1. Conferências =====================
IF @precounit IS NULL OR @vltotal IS NULL OR ISNULL(@qtcomp, 0) <= 0
    SET @erro = @erro + 'Item vendido da nota 117 nao encontrado. ';

IF NOT EXISTS (SELECT 1 FROM ENT_ITENT
                WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = 117 AND DTNOTA = @dtnota
                  AND CODITPROD = @coditprod AND ITEM = 1 AND STATUS = 1 AND CONVERSAO IS NULL AND QTCOMP = @qtcomp)
    SET @erro = @erro + 'Cancelamento 117 fora do estado esperado (STATUS 1, CONVERSAO nula). ';

IF NOT EXISTS (SELECT 1 FROM MOV_ITSAIDA
                WHERE CODFIL = @codfil AND TPNOTA = 251 AND NUMNOTA = 118 AND DTNOTA = @dtnota AND CODITPROD = @coditprod
                  AND STATUS = 2 AND QTEMB IS NULL AND ISNULL(TPPROG, 'N') <> 'S')
    SET @erro = @erro + 'Cupom 118 fora do estado esperado (STATUS 2, QTEMB nulo, TPPROG diferente de S). ';

IF NOT EXISTS (SELECT 1 FROM CAD_TPNOTA WHERE TPNOTA = 12 AND ISNULL(FLVENDA, 'N') = 'N')
    SET @erro = @erro + 'Tipo de nota 12 mudou (FLVENDA). ';

IF @qtemb_cad IS NULL
    SET @erro = @erro + 'Embalagem 0 do produto nao encontrada. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2 a 4. Correção =====================
BEGIN TRY
    BEGIN TRAN;

    -- 2. Cancelamento 117: preço, total e embalagem do item vendido (STATUS não é alterado)
    UPDATE ENT_ITENT
       SET CONVERSAO = @qtemb_venda,
           PRECOUNIT = @precounit,
           VLTOTAL   = @vltotal,
           VLTOTITEM = @vltotal,
           VLOUTRAS  = @vltotal,
           VLOUTRASF = ROUND(@vltotal / @qtcomp, 4)
     WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = 117 AND DTNOTA = @dtnota
       AND CODITPROD = @coditprod AND ITEM = 1 AND CONVERSAO IS NULL;
    IF @@ROWCOUNT <> 1 RAISERROR('Cancelamento 117: esperado 1 registro alterado.', 16, 1);

    -- 3. Cupom 118: embalagem do item (STATUS não é alterado)
    UPDATE MOV_ITSAIDA
       SET QTEMB = @qtemb_cad
     WHERE CODFIL = @codfil AND TPNOTA = 251 AND NUMNOTA = 118 AND DTNOTA = @dtnota AND CODITPROD = @coditprod AND QTEMB IS NULL;
    IF @@ROWCOUNT <> 1 RAISERROR('Cupom 118: esperado 1 registro alterado.', 16, 1);

    -- 4. Conferência: registros corrigidos e estoque/estatística sem mudança
    SET @erro = '';

    IF NOT EXISTS (SELECT 1 FROM ENT_ITENT WHERE CODFIL = @codfil AND TPNOTA = 12 AND SERIE = 'CAN' AND NUMNOTA = 117 AND DTNOTA = @dtnota
                      AND CODITPROD = @coditprod AND CONVERSAO = @qtemb_venda AND VLTOTAL = @vltotal AND STATUS = 1)
        SET @erro = @erro + 'Cancelamento 117 nao ficou correto. ';

    IF NOT EXISTS (SELECT 1 FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND TPNOTA = 251 AND NUMNOTA = 118 AND DTNOTA = @dtnota
                      AND CODITPROD = @coditprod AND QTEMB = @qtemb_cad AND STATUS = 2)
        SET @erro = @erro + 'Cupom 118 nao ficou correto. ';

    IF NOT EXISTS (SELECT 1 FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod
                      AND FISICO = @fisico_antes AND RESFIS = @resfis_antes)
        SET @erro = @erro + 'O estoque do produto mudou. ';

    IF ISNULL((SELECT SUM(ISNULL(QTVENLIQ, 0)) FROM EST_PROD WHERE CODFIL = @codfil AND CODITPROD = @coditprod AND DTVENDA = @dtnota), -1) <> ISNULL(@estprod_antes, -1)
       OR ISNULL((SELECT SUM(ISNULL(QTVENLIQ, 0)) FROM EST_PRODVEN WHERE CODFIL = @codfil AND CODITPROD = @coditprod AND DTVENDA = @dtnota), -1) <> ISNULL(@estprodven_antes, -1)
        SET @erro = @erro + 'A estatistica de venda do produto mudou. ';

    IF @erro <> ''
        RAISERROR('Conferencia final falhou, tudo foi desfeito: %s', 16, 1, @erro);

    COMMIT;
    PRINT 'Corrigidos: cancelamento 117 (ENT_ITENT) e cupom 118 (MOV_ITSAIDA). Estoque e estatistica sem mudanca.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS - cancelamento 117' AS registro, CONVERSAO, PRECOUNIT, VLTOTAL, VLTOTITEM, VLOUTRAS, VLOUTRASF, QTCOMP, QTESTOQUE, STATUS, CUEORIG, DTATUEST
  FROM ENT_ITENT WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = 117 AND DTNOTA = @dtnota AND CODITPROD = @coditprod;
SELECT 'DEPOIS - cupom 118' AS registro, QTEMB, CONVERSAO, QTCOMP, QTESTOQUE, STATUS
  FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND TPNOTA = 251 AND NUMNOTA = 118 AND DTNOTA = @dtnota AND CODITPROD = @coditprod;
SELECT 'DEPOIS - estoque' AS registro, FISICO, RESFIS FROM CAD_PRODLOC WHERE CODFIL = @codfil AND TPDEPOS = 'L' AND CODITPROD = @coditprod;
