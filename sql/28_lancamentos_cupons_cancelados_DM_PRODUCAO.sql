/*
  28 - Lançamentos de caixa dos cupons FIKON já cancelados - PRODUÇÃO  -  24/11/2026 (refeito; antes só 4 lançamentos de 18/11)
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco. Rodar DEPOIS do script 27.

  No cancelamento do Gemco, o lançamento de caixa do cupom fica com STATUS 9 (conferido em 24/11: os 40 cupons do
  PDV cancelados desde outubro estão assim). A SP_FIKON_CANCELAR_NOTA, antes do script 27, deixava o lançamento
  ativo. Em 24/11 eram 8 lançamentos de 7 cupons FIKON cancelados, todos da DM (filial 15):
      3 U05 e 4 U05 (2 lançamentos) e 3 U06 de 18/11; 8 U05 de 19/11; 3 série 2, 40 U05 e 45 U05 de 23/11.

  O que o script faz (numa transação):
    1. Lista TODOS os lançamentos ativos (STATUS <> 9) de cupons FIKON cancelados (MOV_SAIDA STATUS 9, usuário 537,
       NUMPEDVEN 999999), ligados pela filial, tipo, número, série e data (NUMPED 999999, TIPOPED 1).
    2. Passa esses lançamentos para STATUS 9; confere que a quantidade alterada é a mesma da lista e faz o COMMIT.
  O trigger de UPDATE da CXA_LANCTO só recalcula a flag FLVALIDAPAFECF.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @esperados int, @alterados int;

DECLARE @lanc TABLE (CODFIL numeric(5,0), TPNOTA numeric(3,0), NUMNOT numeric(12,0), SERIE varchar(3), DATENT datetime,
                     NUMPRC numeric(3,0), NUMLAN numeric(4,0), DATREF datetime, NUMCOO numeric(12,0));

INSERT INTO @lanc
SELECT c.CODFIL, c.TPNOTA, c.NUMNOT, c.SERIE, c.DATENT, c.NUMPRC, c.NUMLAN, c.DATREF, c.NUMCOO
  FROM MOV_SAIDA s
  JOIN CXA_LANCTO c ON c.CODFIL = s.CODFIL AND c.TPNOTA = s.TPNOTA AND c.NUMNOT = s.NUMNOTA AND c.SERIE = s.SERIE
                   AND c.DATENT = s.DTNOTA AND c.NUMPED = 999999 AND c.TIPOPED = 1
 WHERE s.STATUS = 9 AND s.NUMPEDVEN = 999999 AND s.CODUSER = 537
   AND c.STATUS <> 9;

SET @esperados = (SELECT COUNT(*) FROM @lanc);

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, c.CODFIL, c.NUMNOT, c.SERIE, CONVERT(varchar(10), c.DATENT, 103) AS data, c.NUMLAN, c.CODEVE, c.VALLAN, c.STATUS, c.NUMCXA
  FROM CXA_LANCTO c
  JOIN @lanc l ON l.CODFIL = c.CODFIL AND l.TPNOTA = c.TPNOTA AND l.NUMNOT = c.NUMNOT AND l.SERIE = c.SERIE AND l.DATENT = c.DATENT
              AND l.NUMPRC = c.NUMPRC AND l.NUMLAN = c.NUMLAN AND l.DATREF = c.DATREF
 WHERE c.NUMPED = 999999 AND c.TIPOPED = 1
 ORDER BY c.DATENT, c.CODFIL, c.SERIE, c.NUMNOT, c.NUMLAN;

IF @esperados = 0
BEGIN
    PRINT 'Nenhum lancamento ativo de cupom FIKON cancelado. Nada a fazer.';
    RETURN;
END

-- ===================== 2. Ajuste =====================
BEGIN TRY
    BEGIN TRAN;

    UPDATE c SET STATUS = 9
      FROM CXA_LANCTO c WITH (READCOMMITTED)
      JOIN @lanc l ON l.CODFIL = c.CODFIL AND l.TPNOTA = c.TPNOTA AND l.NUMNOT = c.NUMNOT AND l.SERIE = c.SERIE AND l.DATENT = c.DATENT
                  AND l.NUMPRC = c.NUMPRC AND l.NUMLAN = c.NUMLAN AND l.DATREF = c.DATREF
     WHERE c.NUMPED = 999999 AND c.TIPOPED = 1 AND c.STATUS <> 9;
    SET @alterados = @@ROWCOUNT;

    IF @alterados <> @esperados
        RAISERROR('Conferencia final falhou (%d de %d lancamento(s)); tudo foi desfeito.', 16, 1, @alterados, @esperados);

    COMMIT;
    PRINT CONCAT(@alterados, ' lancamento(s) de cupons FIKON cancelados passaram para STATUS 9.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, c.CODFIL, c.NUMNOT, c.SERIE, CONVERT(varchar(10), c.DATENT, 103) AS data, c.NUMLAN, c.VALLAN, c.STATUS
  FROM CXA_LANCTO c
  JOIN @lanc l ON l.CODFIL = c.CODFIL AND l.TPNOTA = c.TPNOTA AND l.NUMNOT = c.NUMNOT AND l.SERIE = c.SERIE AND l.DATENT = c.DATENT
              AND l.NUMPRC = c.NUMPRC AND l.NUMLAN = c.NUMLAN AND l.DATREF = c.DATREF
 WHERE c.NUMPED = 999999 AND c.TIPOPED = 1
 ORDER BY c.DATENT, c.CODFIL, c.SERIE, c.NUMNOT, c.NUMLAN;
