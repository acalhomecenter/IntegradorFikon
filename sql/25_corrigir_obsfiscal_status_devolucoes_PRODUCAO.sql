/*
  25 - Corrige OBSFISCAL e status da venda das devoluções gravadas pela integração FIKON - PRODUÇÃO  -  18/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco. Rodar depois do script 24.

  As 4 devoluções da integração foram gravadas com o OBSFISCAL usando a série da devolução no lugar da série da
  venda, e as vendas devolvidas por inteiro ficaram com STATUS 7 (parcial) (ver script 24):

    devolução (filial / nº / série / data)   venda                 OBSFISCAL hoje                                  venda
    502 / 20 / 1 / 30/10                       97  U01 de 29/10     "NF: 97 SERIE: 1 DT: 29/10/2026 VALOR: 163,80"   7 (parcial, certo)
    502 / 27 / 1 / 16/11                       120 U01 de 16/11     "NF: 120 SERIE: 1 DT: 16/11/2026 VALOR: 2,00"    7 -> 8
     15 /  1 / 2 / 18/11                       5   U06 de 18/11     "NF: 5 SERIE: 2 DT: 18/11/2026 VALOR: 16,99"     7 -> 8
     15 /  2 / 2 / 18/11                       6   U05 de 18/11     "NF: 6 SERIE: 2 DT: 18/11/2026 VALOR: 21,99"     7 -> 8

  O que o script faz (numa transação):
    1. Confere que as 4 devoluções existem, cada uma com uma única ENT_NOTASAI, e que as vendas estão como acima.
       Se algo estiver diferente, não altera nada.
    2. OBSFISCAL = "NF: <venda> SERIE: <série da venda> DT: <data da venda> VALOR: <total da venda>".
    3. STATUS 8 nas 3 vendas devolvidas por inteiro (saldo 0); a 97 U01 continua 7.
       O trigger de UPDATE da MOV_SAIDA só age quando o STATUS vira 9; 7 -> 8 só registra log.
    4. Confere e faz o COMMIT.
  A ENT_NOTASAI é ligada pela filial, tipo, série, número e data da devolução (sem o remetente), porque o
  remetente da devolução 1 da filial 15 foi trocado no Gemco de 0 para 99226 só na ENT_NOTA/ENT_ITENT.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @erro varchar(1000) = '';
DECLARE @obs int, @st int;

DECLARE @dev TABLE (CODFIL numeric(5,0), NUMNOTA numeric(12,0), SERIE varchar(3), DTNOTA date,
                    NUMNOTASAI numeric(12,0), SERIESAI varchar(3), STATUS_NOVO int);
INSERT INTO @dev VALUES (502, 20, '1', '2026-10-30',  97, 'U01', 7),
                        (502, 27, '1', '2026-11-16', 120, 'U01', 8),
                        ( 15,  1, '2', '2026-11-18',   5, 'U06', 8),
                        ( 15,  2, '2', '2026-11-18',   6, 'U05', 8);

DECLARE @base TABLE (CODFIL numeric(5,0), TPNOTA numeric(3,0), CODREMET numeric(15,0), SERIE varchar(3), NUMNOTA numeric(12,0), DTNOTA date,
                     CODFILSAI numeric(5,0), TPNOTASAI numeric(3,0), NUMNOTASAI numeric(12,0), SERIESAI varchar(3), DTNOTASAI date,
                     VLVENDA numeric(15,2), STATUS_VENDA int, SALDO numeric(15,4), STATUS_NOVO int, OBS_NOVO varchar(200));

INSERT INTO @base
SELECT n.CODFIL, n.TPNOTA, n.CODREMET, n.SERIE, n.NUMNOTA, n.DTNOTA,
       ns.CODFILSAI, ns.TPNOTASAI, ns.NUMNOTASAI, ns.SERIESAI, ns.DTNOTASAI,
       s.VLTOTAL, s.STATUS,
       (SELECT SUM(i.QTCOMP) - SUM(ISNULL(i.QTDEVOL, 0)) FROM MOV_ITSAIDA i
         WHERE i.CODFIL = ns.CODFILSAI AND i.TPNOTA = ns.TPNOTASAI AND i.NUMNOTA = ns.NUMNOTASAI AND i.SERIE = ns.SERIESAI AND i.DTNOTA = ns.DTNOTASAI),
       d.STATUS_NOVO,
       'NF: ' + CONVERT(varchar, ns.NUMNOTASAI) + ' SERIE: ' + ns.SERIESAI + ' DT: ' + CONVERT(varchar, ns.DTNOTASAI, 103)
       + ' VALOR: ' + REPLACE(CONVERT(varchar, CONVERT(numeric(15,2), s.VLTOTAL)), '.', ',')
  FROM @dev d
  JOIN ENT_NOTA n    ON n.CODFIL = d.CODFIL AND n.TPNOTA = 26 AND n.SERIE = d.SERIE AND n.NUMNOTA = d.NUMNOTA AND n.DTNOTA = d.DTNOTA
                    AND n.IDENTPROC = 'DEVOLUCAO REALIZADA VIA INTEGRADOR FIKON'
  JOIN ENT_NOTASAI ns ON ns.CODFIL = n.CODFIL AND ns.TPNOTA = n.TPNOTA AND ns.SERIE = n.SERIE AND ns.NUMNOTA = n.NUMNOTA AND ns.DTNOTA = n.DTNOTA
                     AND ns.NUMNOTASAI = d.NUMNOTASAI AND ns.SERIESAI = d.SERIESAI
  JOIN MOV_SAIDA s   ON s.CODFIL = ns.CODFILSAI AND s.TPNOTA = ns.TPNOTASAI AND s.NUMNOTA = ns.NUMNOTASAI AND s.SERIE = ns.SERIESAI AND s.DTNOTA = ns.DTNOTASAI;

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, b.CODFIL, b.NUMNOTA AS devolucao, b.SERIE, b.NUMNOTASAI AS venda, b.SERIESAI, n.OBSFISCAL, b.OBS_NOVO,
       b.STATUS_VENDA, b.SALDO, b.STATUS_NOVO
  FROM @base b
  JOIN ENT_NOTA n ON n.CODFIL = b.CODFIL AND n.TPNOTA = b.TPNOTA AND n.CODREMET = b.CODREMET AND n.SERIE = b.SERIE AND n.NUMNOTA = b.NUMNOTA AND n.DTNOTA = b.DTNOTA
 ORDER BY b.DTNOTA, b.CODFIL, b.NUMNOTA;

-- ===================== 1. Conferências =====================
IF (SELECT COUNT(*) FROM @base) <> 4
    SET @erro = @erro + 'Esperadas 4 devolucoes com uma ENT_NOTASAI cada (achou ' + CAST((SELECT COUNT(*) FROM @base) AS varchar(5)) + '). ';

IF EXISTS (SELECT 1 FROM @base WHERE STATUS_VENDA <> 7)
    SET @erro = @erro + 'Alguma venda nao esta com STATUS 7. ';

IF EXISTS (SELECT 1 FROM @base WHERE (STATUS_NOVO = 8 AND SALDO <> 0) OR (STATUS_NOVO = 7 AND SALDO <= 0))
    SET @erro = @erro + 'Saldo devolvido de alguma venda diferente do esperado. ';

IF EXISTS (SELECT 1 FROM @base WHERE OBS_NOVO IS NULL)
    SET @erro = @erro + 'Nao foi possivel montar o OBSFISCAL de alguma devolucao. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2 e 3. Correção =====================
BEGIN TRY
    BEGIN TRAN;

    UPDATE n SET OBSFISCAL = b.OBS_NOVO
      FROM ENT_NOTA n
      JOIN @base b ON n.CODFIL = b.CODFIL AND n.TPNOTA = b.TPNOTA AND n.CODREMET = b.CODREMET AND n.SERIE = b.SERIE
                  AND n.NUMNOTA = b.NUMNOTA AND n.DTNOTA = b.DTNOTA;
    SET @obs = @@ROWCOUNT;

    UPDATE s SET STATUS = 8
      FROM MOV_SAIDA s
      JOIN @base b ON s.CODFIL = b.CODFILSAI AND s.TPNOTA = b.TPNOTASAI AND s.NUMNOTA = b.NUMNOTASAI AND s.SERIE = b.SERIESAI
                  AND s.DTNOTA = b.DTNOTASAI
     WHERE b.STATUS_NOVO = 8 AND s.STATUS = 7;
    SET @st = @@ROWCOUNT;

    IF @obs <> 4 OR @st <> 3
        RAISERROR('Conferencia final falhou (%d OBSFISCAL, %d status); tudo foi desfeito.', 16, 1, @obs, @st);

    COMMIT;
    PRINT 'OBSFISCAL das 4 devolucoes corrigido e 3 vendas com STATUS 8.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, b.CODFIL, b.NUMNOTA AS devolucao, b.SERIE, n.OBSFISCAL, b.NUMNOTASAI AS venda, b.SERIESAI, s.STATUS AS status_venda
  FROM @base b
  JOIN ENT_NOTA n  ON n.CODFIL = b.CODFIL AND n.TPNOTA = b.TPNOTA AND n.CODREMET = b.CODREMET AND n.SERIE = b.SERIE AND n.NUMNOTA = b.NUMNOTA AND n.DTNOTA = b.DTNOTA
  JOIN MOV_SAIDA s ON s.CODFIL = b.CODFILSAI AND s.TPNOTA = b.TPNOTASAI AND s.NUMNOTA = b.NUMNOTASAI AND s.SERIE = b.SERIESAI AND s.DTNOTA = b.DTNOTASAI
 ORDER BY b.DTNOTA, b.CODFIL, b.NUMNOTA;
