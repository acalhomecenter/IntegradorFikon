/* =====================================================================================================
   Script 38 (25/11/2026) - Bandeiras de crédito da FIKON na dbAplicativos.dbo.CASH_CONVENIADAS

   Erro: "Bandeira American Express não encontrada em CASH_CONVENIADAS para o pedido FIKON 2105359."
   Os pedidos pagos no cartão de crédito (Integrador -> SP_FIKON_ATUALIZA_STATUS_PEDIDO) procuram a bandeira pelo
   nome na CASH_CONVENIADAS. A tabela tinha só "AMEX"; a FIKON manda "American Express".

   Inclui os nomes de crédito que já estão no de-para dos cupons (dbgemco.dbo.FIKON_DEPARA_BANDEIRA) e faltam
   na CASH_CONVENIADAS, com o mesmo CODCON:
     AMERICAN EXPRESS -> 5 | MASTER, MASTER CREDITO, MASTERCARD CREDITO -> 1 | VISA CREDITO -> 2

   Só insere o que não existe (pode rodar de novo). Rodar no SSMS conectado na produção.
   ===================================================================================================== */

USE [dbAplicativos]
GO

INSERT INTO dbo.CASH_CONVENIADAS (BANDEIRA, CODCON, TIPO)
SELECT v.BANDEIRA, v.CODCON, 'C'
  FROM (VALUES ('AMERICAN EXPRESS', 5),
               ('MASTER', 1),
               ('MASTER CREDITO', 1),
               ('MASTERCARD CREDITO', 1),
               ('VISA CREDITO', 2)) v (BANDEIRA, CODCON)
 WHERE NOT EXISTS (SELECT 1 FROM dbo.CASH_CONVENIADAS c
                    WHERE UPPER(LTRIM(RTRIM(c.BANDEIRA))) = v.BANDEIRA AND c.TIPO = 'C');

SELECT ID, BANDEIRA, CODCON, TIPO FROM dbo.CASH_CONVENIADAS ORDER BY TIPO, BANDEIRA;
GO
