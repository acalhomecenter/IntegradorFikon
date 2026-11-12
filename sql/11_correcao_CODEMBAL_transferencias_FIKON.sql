/*
  11 - Correção do CODEMBAL nas transferências já gravadas pela integração FIKON  -  12/11/2026

  Problema: o pedido 13296783 (filial 15 -> 1, nota 22) não mostrava os itens na tela do Gemco.
  As telas do Gemco ligam MOV_ITPED.CODEMBAL = CAD_EMBAL.CODEMBAL, e a procedure da integração
  gravava CODEMBAL nulo na MOV_ITPED e na MOV_ITSAIDA. Com CODEMBAL nulo a ligação não encontra a
  embalagem e o item some da tela. O Gemco grava sempre 0 ou 1.
  A procedure foi corrigida no script 10 (rodar o 10 de novo antes ou depois deste).

  O que este script faz: CODEMBAL = 0 nos itens de pedido (MOV_ITPED) e de nota (MOV_ITSAIDA) das
  transferências gravadas pela integração (MOV_PEDIDO.IDENTPROC 'INTEGRADOR FIKON - TRANSFERENCIA%')
  que estão com CODEMBAL nulo. Não mexe em estoque: os triggers de UPDATE só agem quando muda
  QTCOMP, STATUS ou QTDEVOL.

  Como rodar: no SSMS, no banco dbgemco, o script INTEIRO (F5). Ele mostra antes/depois e só confirma
  (COMMIT) se não der erro.
*/
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#ped') IS NOT NULL DROP TABLE #ped

SELECT p.CODFIL, p.TIPOPED, p.NUMPEDVEN
  INTO #ped
  FROM dbo.MOV_PEDIDO p
 WHERE p.TIPOPED = 2
   AND p.DTPEDIDO >= '20261101'
   AND p.IDENTPROC LIKE 'INTEGRADOR FIKON - TRANSFERENCIA%'

SELECT 'ANTES' etapa, p.CODFIL, p.NUMPEDVEN,
       (SELECT COUNT(*) FROM dbo.MOV_ITPED i WHERE i.CODFIL = p.CODFIL AND i.TIPOPED = 2 AND i.NUMPEDVEN = p.NUMPEDVEN AND i.CODEMBAL IS NULL) itped_codembal_nulo,
       (SELECT COUNT(*) FROM dbo.MOV_ITSAIDA s WHERE s.FILPED = p.CODFIL AND s.TPNOTA = 144 AND s.NUMPEDVEN = p.NUMPEDVEN AND s.CODEMBAL IS NULL) itsaida_codembal_nulo
  FROM #ped p
 ORDER BY p.NUMPEDVEN

BEGIN TRAN

BEGIN TRY
    UPDATE i WITH (READCOMMITTED)
       SET CODEMBAL = 0
      FROM dbo.MOV_ITPED i
      JOIN #ped p ON p.CODFIL = i.CODFIL AND p.TIPOPED = i.TIPOPED AND p.NUMPEDVEN = i.NUMPEDVEN
     WHERE i.CODEMBAL IS NULL

    PRINT CONVERT(varchar(10), @@ROWCOUNT) + ' item(ns) de pedido corrigido(s) na MOV_ITPED.'

    UPDATE s WITH (READCOMMITTED)
       SET CODEMBAL = 0
      FROM dbo.MOV_ITSAIDA s
      JOIN #ped p ON p.CODFIL = s.FILPED AND p.NUMPEDVEN = s.NUMPEDVEN
     WHERE s.TPNOTA = 144
       AND s.CODEMBAL IS NULL

    PRINT CONVERT(varchar(10), @@ROWCOUNT) + ' item(ns) de nota corrigido(s) na MOV_ITSAIDA.'

    COMMIT
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK
    SELECT 'ERRO (nada foi alterado): ' + ERROR_MESSAGE() AS resultado
END CATCH

SELECT 'DEPOIS' etapa, p.CODFIL, p.NUMPEDVEN,
       (SELECT COUNT(*) FROM dbo.MOV_ITPED i WHERE i.CODFIL = p.CODFIL AND i.TIPOPED = 2 AND i.NUMPEDVEN = p.NUMPEDVEN AND i.CODEMBAL IS NULL) itped_codembal_nulo,
       (SELECT COUNT(*) FROM dbo.MOV_ITSAIDA s WHERE s.FILPED = p.CODFIL AND s.TPNOTA = 144 AND s.NUMPEDVEN = p.NUMPEDVEN AND s.CODEMBAL IS NULL) itsaida_codembal_nulo
  FROM #ped p
 ORDER BY p.NUMPEDVEN
