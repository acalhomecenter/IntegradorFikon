/*
  22 - Caixa nos 2 lançamentos FIKON da DM (filial 15, série U05) de 18/11/2026 - PRODUÇÃO
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  Os dois lançamentos foram gravados antes do script 21, sem caixa:
      nota 2  série U05  R$ 57,99  forma 43
      nota 3  série U05  R$ 21,90  forma 1 (dinheiro)
  com NUMCXA, NUMMOV e CODOPER nulos e CODFILCXA 0.

  O que o script faz (numa transação), com a mesma regra do script 21:
    NUMCXA    = FIKON_CAD_CAIXA.CAIXA   (filial 15 + série U05 -> caixa 4)
    CODOPER   = FIKON_CAD_CAIXA.CODOPER (operador 24)
    CODFILCXA = 15 (filial da nota)
    NUMMOV    = movimento do caixa 4 em 18/11 na CXA_MOVIMENTO (o aberto primeiro); sem movimento, 1.
  1. Confere que são exatamente os 2 lançamentos, ainda sem caixa, e que existe o de-para.
     Se algo estiver diferente, não altera nada.
  2. Atualiza só esses 2 lançamentos, confere e faz o COMMIT.
  O trigger de UPDATE da CXA_LANCTO só recalcula a flag FLVALIDAPAFECF.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @codfil numeric(5,0) = 15, @serie varchar(3) = 'U05', @data date = '2026-11-18';
DECLARE @numcxa numeric(3,0), @codoper numeric(4,0), @nummov numeric(2,0);
DECLARE @erro varchar(1000) = '';
DECLARE @alterados int;

-- de-para (mesma consulta da proc: filial + série)
SELECT TOP (1) @numcxa = c.CAIXA, @codoper = c.CODOPER
  FROM FIKON_CAD_CAIXA c
 WHERE c.CODFIL = @codfil AND c.SERIE = @serie AND c.CAIXA IS NOT NULL
 ORDER BY c.ID;

SELECT TOP (1) @nummov = m.NUMMOV
  FROM CXA_MOVIMENTO m
 WHERE m.CODFIL = @codfil AND m.NUMCXA = @numcxa AND m.DATAINI = @data
 ORDER BY CASE WHEN m.SITUACAO = 'I' THEN 0 ELSE 1 END,
          CASE WHEN m.CODOPER = @codoper THEN 0 ELSE 1 END,
          m.NUMMOV DESC;
IF @nummov IS NULL SET @nummov = 1;

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, NUMNOT, SERIE, NUMLAN, FORMA, VALLAN, STATUS, NUMCXA, NUMMOV, CODOPER, CODFILCXA,
       @numcxa AS novo_numcxa, @nummov AS novo_nummov, @codoper AS novo_codoper, @codfil AS novo_codfilcxa
  FROM CXA_LANCTO
 WHERE CODFIL = @codfil AND SERIE = @serie AND DATENT = @data
 ORDER BY NUMNOT;

-- ===================== 1. Conferências =====================
IF @numcxa IS NULL OR @codoper IS NULL
    SET @erro = @erro + 'Sem de-para na FIKON_CAD_CAIXA para filial 15 / serie U05. ';

IF (SELECT COUNT(*) FROM CXA_LANCTO
     WHERE CODFIL = @codfil AND SERIE = @serie AND DATENT = @data AND TPNOTA = 251 AND NUMPED = 999999) <> 2
    SET @erro = @erro + 'Esperados 2 lancamentos U05 em 18/11 na filial 15. ';

IF (SELECT COUNT(*) FROM CXA_LANCTO
     WHERE CODFIL = @codfil AND SERIE = @serie AND DATENT = @data AND TPNOTA = 251 AND NUMPED = 999999
       AND NUMNOT IN (2, 3) AND NUMCXA IS NULL AND NUMMOV IS NULL AND CODOPER IS NULL AND ISNULL(CODFILCXA, 0) = 0) <> 2
    SET @erro = @erro + 'Os lancamentos das notas 2 e 3 nao estao sem caixa (ja ajustados?). ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2. Ajuste =====================
BEGIN TRY
    BEGIN TRAN;

    UPDATE CXA_LANCTO WITH (READCOMMITTED)
       SET NUMCXA = @numcxa, NUMMOV = @nummov, CODOPER = @codoper, CODFILCXA = @codfil
     WHERE CODFIL = @codfil AND SERIE = @serie AND DATENT = @data AND TPNOTA = 251 AND NUMPED = 999999
       AND NUMNOT IN (2, 3) AND NUMCXA IS NULL AND NUMMOV IS NULL AND CODOPER IS NULL AND ISNULL(CODFILCXA, 0) = 0;
    SET @alterados = @@ROWCOUNT;

    IF @alterados <> 2
        RAISERROR('Conferencia final falhou (%d lancamento(s) alterado(s)); tudo foi desfeito.', 16, 1, @alterados);

    COMMIT;
    PRINT 'Lancamentos das notas 2 e 3 (filial 15, serie U05, 18/11) com caixa ajustado.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, NUMNOT, SERIE, NUMLAN, FORMA, VALLAN, STATUS, NUMCXA, NUMMOV, CODOPER, CODFILCXA
  FROM CXA_LANCTO
 WHERE CODFIL = @codfil AND SERIE = @serie AND DATENT = @data
 ORDER BY NUMNOT;
