/*
  26 - Remetente da devolução 1 série 2 da DM (filial 15, 18/11/2026) na ENT_NOTASAI / ENT_ITNOTASAI - PRODUÇÃO
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  O que aconteceu:
    A integração gravou a devolução com o remetente da venda (NFC-e 5 U06, consumidor = cliente 0) nas quatro
    tabelas: ENT_NOTA, ENT_ITENT, ENT_NOTASAI e ENT_ITNOTASAI.
    Depois o remetente foi trocado no Gemco para o cliente 99226 só na ENT_NOTA e na ENT_ITENT.
    Ao gerar o crédito da devolução (GEMCONEGFINCRC, log de 18/11 18:03), o Gemco grava o título e o lançamento,
    marca FLINTEGRACPG = 'R' na ENT_NOTA e depois na ENT_NOTASAI, procurando pelo remetente 99226.
    A ENT_NOTASAI está com 0, o update não acha a linha e o Gemco desfaz tudo (rollback).
    Por isso a devolução 1 ficou com FLINTEGRACPG nulo e sem crédito.

  O que o script faz (numa transação):
    1. Confere: ENT_NOTA da devolução com remetente 99226; uma única ENT_NOTASAI (venda 5 U06) e o(s) item(ns)
       da ENT_ITNOTASAI ainda com remetente 0; nenhuma linha já com 99226. Se algo estiver diferente, não altera nada.
    2. Troca o remetente 0 -> 99226 na ENT_NOTASAI e na ENT_ITNOTASAI dessa devolução.
       Essas tabelas não têm FK nem trigger de UPDATE.
    3. Confere e faz o COMMIT.
  Depois: gerar de novo o crédito da devolução 1 no Gemco.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @codfil numeric(5,0) = 15, @tpnota numeric(3,0) = 26, @serie varchar(3) = '2', @numnota numeric(12,0) = 1,
        @dtnota date = '2026-11-18', @remet_antigo numeric(15,0) = 0, @remet_novo numeric(15,0) = 99226;
DECLARE @erro varchar(1000) = '';
DECLARE @cab int, @itens int, @itens_esperados int;

-- ===================== ANTES =====================
SELECT 'ANTES ENT_NOTA' AS tabela, CODREMET, FLINTEGRACPG FROM ENT_NOTA
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota;
SELECT 'ANTES ENT_NOTASAI' AS tabela, CODREMET, NUMNOTASAI, SERIESAI, FLINTEGRACPG FROM ENT_NOTASAI
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota;
SELECT 'ANTES ENT_ITNOTASAI' AS tabela, CODREMET, CODITPROD, ITEM, QTDEVOL FROM ENT_ITNOTASAI
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota;

-- ===================== 1. Conferências =====================
IF NOT EXISTS (SELECT 1 FROM ENT_NOTA
                WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota
                  AND CODREMET = @remet_novo AND IDENTPROC = 'DEVOLUCAO REALIZADA VIA INTEGRADOR FIKON')
    SET @erro = @erro + 'ENT_NOTA da devolucao 1 nao esta com remetente 99226. ';

IF (SELECT COUNT(*) FROM ENT_NOTASAI
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota) <> 1
   OR NOT EXISTS (SELECT 1 FROM ENT_NOTASAI
                   WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota
                     AND CODREMET = @remet_antigo AND NUMNOTASAI = 5 AND SERIESAI = 'U06')
    SET @erro = @erro + 'ENT_NOTASAI da devolucao 1 nao esta como esperado (uma linha, remetente 0, venda 5 U06). ';

SELECT @itens_esperados = COUNT(*) FROM ENT_ITNOTASAI
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota;
IF @itens_esperados = 0
   OR EXISTS (SELECT 1 FROM ENT_ITNOTASAI
               WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota
                 AND CODREMET <> @remet_antigo)
    SET @erro = @erro + 'ENT_ITNOTASAI da devolucao 1 sem itens ou com remetente diferente de 0. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2 e 3. Ajuste =====================
BEGIN TRY
    BEGIN TRAN;

    UPDATE ENT_NOTASAI WITH (READCOMMITTED) SET CODREMET = @remet_novo
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota
       AND CODREMET = @remet_antigo;
    SET @cab = @@ROWCOUNT;

    UPDATE ENT_ITNOTASAI WITH (READCOMMITTED) SET CODREMET = @remet_novo
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota
       AND CODREMET = @remet_antigo;
    SET @itens = @@ROWCOUNT;

    IF @cab <> 1 OR @itens <> @itens_esperados
        RAISERROR('Conferencia final falhou (%d ENT_NOTASAI, %d ENT_ITNOTASAI); tudo foi desfeito.', 16, 1, @cab, @itens);

    COMMIT;
    PRINT 'Remetente 99226 gravado na ENT_NOTASAI e na ENT_ITNOTASAI da devolucao 1 (filial 15). Gerar o credito de novo no Gemco.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS ENT_NOTASAI' AS tabela, CODREMET, NUMNOTASAI, SERIESAI, FLINTEGRACPG FROM ENT_NOTASAI
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota;
SELECT 'DEPOIS ENT_ITNOTASAI' AS tabela, CODREMET, CODITPROD, ITEM, QTDEVOL FROM ENT_ITNOTASAI
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota AND DTNOTA = @dtnota;
