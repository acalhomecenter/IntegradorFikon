/* =====================================================================================================
   Script 37 (25/11/2026) - Tira da fila de faturamento o pedido Gemco 14275149 (FIKON 2099486)

   O pedido foi cancelado no Gemco (MOV_PEDIDO/MOV_ITPED STATUS 9, nota 75 U05 cancelada, lançamento STATUS 9)
   e a FIKON responde 404 "Pedido 2099486 não encontrado na base de dados". Como estava "LIBERADO CXA", o
   Integrador consultava a FIKON a cada ciclo e gravava o mesmo erro (mais de 2.400 linhas na FIKON_LOG_INTEGRADOR).

   O Integrador corrigido já faz isso sozinho (erro na consulta + pedido cancelado/faturado no Gemco = sai da fila);
   este script só resolve agora, antes de publicar a nova versão. Só altera se o pedido ainda estiver cancelado.
   ===================================================================================================== */

USE [dbgemco]
GO

UPDATE f
   SET f.[STATUS] = 'CANCELADO NO GEMCO'
  FROM dbo.FIKON_INTEGRACAO_PEDIDO f
  JOIN dbo.MOV_PEDIDO p ON p.NUMPEDVEN = f.pedido_gemco
 WHERE f.pedido_gemco = 14275149
   AND f.pedido_fikon = 2099486
   AND f.[STATUS] = 'LIBERADO CXA'
   AND p.STATUS = 9;

SELECT id, pedido_gemco, pedido_fikon, [STATUS] FROM dbo.FIKON_INTEGRACAO_PEDIDO WHERE pedido_gemco = 14275149;
GO
