/*
  15 - Remove as notas sem itens gravadas por engano pelo Integrador Fikon - PRODUÇÃO  -  16/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  O que aconteceu:
    Em 16/11/2026, às 09:19, o Integrador (versão com "FATURADO PARCIAL" de volta na fila de faturamento)
    reprocessou dois pedidos de teste de julho e gravou dois cabeçalhos de nota que não existem:
      - nota 6, série 1, pedido 13613768 (FIKON 730762): NF-e 6 da FIKON de 22/07, nunca integrada; os itens
        do pedido já tinham sido faturados no Gemco (notas 797767 da filial 5 e 7/U01 da 502).
      - nota 1567300, série 1, pedido 13607347 (FIKON 444376): documento da FIKON SEM chave de acesso (não é
        NF-e/NFC-e); o pedido está cancelado no Gemco.
    As duas ficaram com DTNOTA = 16/11/2026 (a proc usa a data do dia), STATUS 2, sem itens e sem financeiro.
    O Integrador corrigido não grava mais nota sem itens a faturar nem documento sem chave.

  O que o script faz (numa transação):
    1. Confere que as duas notas estão exatamente como acima: filial 502, TPNOTA 251, série 1, data 16/11/2026,
       gravadas pelo Integrador (CODUSER 537) hoje, sem itens, sem lançamento de caixa e sem vasilhame.
       Se algo estiver diferente, não altera nada.
    2. Apaga os dois cabeçalhos da MOV_SAIDA. Os triggers de DELETE da MOV_SAIDA só registram log
       (PAF-ECF, se ativo, e a fila de integração EAI).
    3. Confere que as duas sumiram e só então faz o COMMIT.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @erro varchar(1000) = '';
DECLARE @apagadas int;

DECLARE @notas TABLE (NUMNOTA numeric(12,0), NUMPEDVEN numeric(12,0), CHAVENFE varchar(44));
INSERT INTO @notas VALUES (6, 13613768, '23260707201916001716550010000000061007686955'),
                          (1567300, 13607347, '');

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, s.CODFIL, s.TPNOTA, s.NUMNOTA, s.SERIE, CONVERT(varchar(10), s.DTNOTA, 103) AS dtnota, s.NUMPEDVEN, s.STATUS,
       s.CODUSER, s.DATAHORAUTC AS gravada_em, s.VLTOTAL, s.CHAVENFE,
       (SELECT COUNT(*) FROM MOV_ITSAIDA i WHERE i.CODFIL = s.CODFIL AND i.TPNOTA = s.TPNOTA AND i.NUMNOTA = s.NUMNOTA AND i.SERIE = s.SERIE AND i.DTNOTA = s.DTNOTA) AS itens,
       (SELECT COUNT(*) FROM CXA_LANCTO c WHERE c.CODFIL = s.CODFIL AND c.TPNOTA = s.TPNOTA AND c.NUMNOT = s.NUMNOTA AND c.SERIE = s.SERIE) AS lanctos_caixa
  FROM MOV_SAIDA s
  JOIN @notas n ON n.NUMNOTA = s.NUMNOTA
 WHERE s.CODFIL = 502 AND s.TPNOTA = 251 AND s.SERIE = '1' AND s.DTNOTA = '2026-11-16';

-- ===================== 1. Conferências =====================
IF (SELECT COUNT(*)
      FROM MOV_SAIDA s
      JOIN @notas n ON n.NUMNOTA = s.NUMNOTA AND n.NUMPEDVEN = s.NUMPEDVEN AND ISNULL(s.CHAVENFE, '') = n.CHAVENFE
     WHERE s.CODFIL = 502 AND s.TPNOTA = 251 AND s.SERIE = '1' AND s.DTNOTA = '2026-11-16'
       AND s.CODUSER = 537 AND s.STATUS = 2 AND s.DATAHORAUTC LIKE '2026-11-16%') <> 2
    SET @erro = @erro + 'As duas notas nao estao como esperado (filial 502, serie 1, 16/11, Integrador, STATUS 2). ';

IF EXISTS (SELECT 1 FROM MOV_ITSAIDA i JOIN @notas n ON n.NUMNOTA = i.NUMNOTA
            WHERE i.CODFIL = 502 AND i.TPNOTA = 251 AND i.SERIE = '1' AND i.DTNOTA = '2026-11-16')
    SET @erro = @erro + 'Uma das notas tem itens. ';

IF EXISTS (SELECT 1 FROM CXA_LANCTO c JOIN @notas n ON n.NUMNOTA = c.NUMNOT
            WHERE c.CODFIL = 502 AND c.TPNOTA = 251 AND c.SERIE = '1')
    SET @erro = @erro + 'Uma das notas tem lancamento de caixa. ';

IF EXISTS (SELECT 1 FROM MOV_SAIDA_VASILHAME v JOIN @notas n ON n.NUMNOTA = v.NUMNOTA WHERE v.CODFIL = 502)
    SET @erro = @erro + 'Uma das notas tem vasilhame. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2 e 3. Remoção =====================
BEGIN TRY
    BEGIN TRAN;

    DELETE s
      FROM MOV_SAIDA s
      JOIN @notas n ON n.NUMNOTA = s.NUMNOTA AND n.NUMPEDVEN = s.NUMPEDVEN AND ISNULL(s.CHAVENFE, '') = n.CHAVENFE
     WHERE s.CODFIL = 502 AND s.TPNOTA = 251 AND s.SERIE = '1' AND s.DTNOTA = '2026-11-16'
       AND s.CODUSER = 537 AND s.STATUS = 2;
    SET @apagadas = @@ROWCOUNT;

    IF @apagadas <> 2
       OR EXISTS (SELECT 1 FROM MOV_SAIDA s JOIN @notas n ON n.NUMNOTA = s.NUMNOTA
                   WHERE s.CODFIL = 502 AND s.TPNOTA = 251 AND s.SERIE = '1' AND s.DTNOTA = '2026-11-16')
        RAISERROR('Conferencia final falhou (%d nota(s) apagada(s)); tudo foi desfeito.', 16, 1, @apagadas);

    COMMIT;
    PRINT 'Notas 6 e 1567300 (filial 502, serie 1, 16/11/2026) removidas.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, COUNT(*) AS notas_restantes
  FROM MOV_SAIDA s
  JOIN @notas n ON n.NUMNOTA = s.NUMNOTA
 WHERE s.CODFIL = 502 AND s.TPNOTA = 251 AND s.SERIE = '1' AND s.DTNOTA = '2026-11-16';
