/*
  30 - Preenche NUMNFE, DIGNFE, NUMCOO e NUMCCF dos cupons FIKON já gravados - PRODUÇÃO  -  19/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco. Rodar DEPOIS do script 29.

  Cupons gravados pela integração FIKON (usuário 537, NUMPEDVEN 999999, TPNOTA 251) com NUMNFE vazio.
  Em 19/11 eram 19 (18 da DM e 1 da filial 502), ativos e cancelados.
  Mesma regra do PDV do Gemco (e do script 29):
      NUMNFE = número da nota, DIGNFE = posição 44 da chave, NUMCOO = posições 36-43 da chave, NUMCCF = 0.
  Só entra cupom com chave de 44 dígitos e modelo 65 (NFC-e) na chave.

  O que o script faz (numa transação):
    1. Lista os cupons que serão ajustados (ANTES), com os valores novos.
    2. Atualiza só esses; confere que a quantidade alterada é a mesma da lista e faz o COMMIT.
  Os triggers de UPDATE da MOV_SAIDA não reagem a esses campos (só gravam log de alteração).

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @esperados int, @alterados int;

DECLARE @cupons TABLE (CODFIL numeric(5,0), TPNOTA numeric(3,0), NUMNOTA numeric(12,0), SERIE varchar(3), DTNOTA date,
                       CHAVENFE varchar(44), NUMNFE numeric(9,0), DIGNFE numeric(1,0), NUMCOO numeric(9,0));

INSERT INTO @cupons
SELECT s.CODFIL, s.TPNOTA, s.NUMNOTA, s.SERIE, s.DTNOTA, s.CHAVENFE,
       s.NUMNOTA,
       CONVERT(numeric(1,0), SUBSTRING(s.CHAVENFE, 44, 1)),
       CONVERT(numeric(9,0), SUBSTRING(s.CHAVENFE, 36, 8))
  FROM MOV_SAIDA s
 WHERE s.CODUSER = 537 AND s.NUMPEDVEN = 999999 AND s.TPNOTA = 251
   AND ISNULL(s.NUMNFE, 0) = 0
   AND LEN(s.CHAVENFE) = 44 AND s.CHAVENFE NOT LIKE '%[^0-9]%'
   AND SUBSTRING(s.CHAVENFE, 21, 2) = '65'
   AND s.NUMNOTA <= 999999999;

SET @esperados = (SELECT COUNT(*) FROM @cupons);

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, c.CODFIL, c.NUMNOTA, c.SERIE, CONVERT(varchar(10), c.DTNOTA, 103) AS dtnota, s.STATUS,
       s.NUMNFE AS numnfe_atual, c.NUMNFE AS numnfe_novo, c.DIGNFE AS dignfe_novo, c.NUMCOO AS numcoo_novo, c.CHAVENFE
  FROM @cupons c
  JOIN MOV_SAIDA s ON s.CODFIL = c.CODFIL AND s.TPNOTA = c.TPNOTA AND s.NUMNOTA = c.NUMNOTA AND s.SERIE = c.SERIE AND s.DTNOTA = c.DTNOTA
 ORDER BY c.CODFIL, c.SERIE, c.NUMNOTA;

IF @esperados = 0
BEGIN
    PRINT 'Nenhum cupom FIKON sem NUMNFE. Nada a fazer.';
    RETURN;
END

-- ===================== 2. Ajuste =====================
BEGIN TRY
    BEGIN TRAN;

    UPDATE s
       SET NUMNFE = c.NUMNFE, DIGNFE = c.DIGNFE, NUMCOO = c.NUMCOO, NUMCCF = 0
      FROM MOV_SAIDA s WITH (READCOMMITTED)
      JOIN @cupons c ON s.CODFIL = c.CODFIL AND s.TPNOTA = c.TPNOTA AND s.NUMNOTA = c.NUMNOTA AND s.SERIE = c.SERIE
                    AND s.DTNOTA = c.DTNOTA AND s.CHAVENFE = c.CHAVENFE
     WHERE ISNULL(s.NUMNFE, 0) = 0;
    SET @alterados = @@ROWCOUNT;

    IF @alterados <> @esperados
        RAISERROR('Conferencia final falhou (%d de %d cupom(ns)); tudo foi desfeito.', 16, 1, @alterados, @esperados);

    COMMIT;
    PRINT CONCAT(@alterados, ' cupom(ns) FIKON com NUMNFE, DIGNFE, NUMCOO e NUMCCF preenchidos.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, s.CODFIL, s.NUMNOTA, s.SERIE, CONVERT(varchar(10), s.DTNOTA, 103) AS dtnota, s.STATUS,
       s.NUMNFE, s.DIGNFE, s.NUMCOO, s.NUMCCF
  FROM @cupons c
  JOIN MOV_SAIDA s ON s.CODFIL = c.CODFIL AND s.TPNOTA = c.TPNOTA AND s.NUMNOTA = c.NUMNOTA AND s.SERIE = c.SERIE AND s.DTNOTA = c.DTNOTA
 ORDER BY s.CODFIL, s.SERIE, s.NUMNOTA;
