/* =====================================================================================================
   Script 36 (24/11/2026) - Cupons da FIKON: CXA_LANCTO gravada com STATUS 2

   SP_FIKON_NOTA_GRAVAR_FINANCEIRO (grava o financeiro dos cupons integrados da FIKON) chamava a
   SPI_LANCTOAF com @STATUS = 0. Passa a gravar @STATUS = 2, como os cupons do PDV.

   Conferido antes:
     - SPI_LANCTOAF só repassa o @STATUS para o INSERT da CXA_LANCTO;
     - a trigger CXA_LANCTO_TR_INS, com STATUS 2/3, troca o CODEVE pelo CAD_TPNOTA.CODEVERECEBCXA, que é NULL
       para o TPNOTA 251 (e 252) -> o CODEVE (= forma) do cupom não muda;
     - o cancelamento (SP_FIKON_CANCELAR_NOTA, script 27) continua levando o lançamento para STATUS 9.

   Parte 1: altera só a linha "@STATUS = 0" da proc. O texto atual é conferido pelo hash (versão do script 21);
            se a proc estiver diferente, nada é alterado. Guarda uma cópia: SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP36.
   Parte 2: lançamentos de cupom FIKON que já ficaram com STATUS 0 (nota ativa) passam para 2.

   Rodar no SSMS conectado na produção (dbgemco). Pode rodar de novo sem efeito.
   ===================================================================================================== */

USE [dbgemco]
GO

/* ------------------------------- Parte 1: proc -------------------------------------------------- */
DECLARE @d nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO'));
DECLARE @h_atual varbinary(32) = HASHBYTES('SHA2_256', @d);
DECLARE @antes nvarchar(100) = N'@STATUS          = 0,';
DECLARE @depois nvarchar(100) = N'@STATUS          = 2,      -- script 36: lançamento do cupom já recebido (antes 0)';
DECLARE @b nvarchar(max);

IF CHARINDEX(N'-- script 36', @d) > 0
BEGIN
    PRINT 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO ja esta com o script 36. Nada a fazer na proc.';
END
ELSE IF @h_atual <> 0xA116BF4E7F301CFAD3AC510146C6490D74459FD79F5AF5270DF5B6C2E9A03BB7
BEGIN
    RAISERROR('SP_FIKON_NOTA_GRAVAR_FINANCEIRO diferente da versao esperada (script 21). Nada alterado.', 16, 1);
END
ELSE IF (LEN(@d) - LEN(REPLACE(@d, @antes, N''))) / LEN(@antes) <> 1
BEGIN
    RAISERROR('Trecho "@STATUS = 0," nao encontrado uma unica vez na proc. Nada alterado.', 16, 1);
END
ELSE
BEGIN
    -- cópia da versão atual
    IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP36') IS NULL
    BEGIN
        SET @b = REPLACE(@d, N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO]', N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP36]');
        EXEC sys.sp_executesql @b;
    END

    SET @d = REPLACE(@d, @antes, @depois);
    SET @d = REPLACE(@d,
        N'-- dbgemco.dbo.FIKON_CAD_CAIXA (filial + serie da nota -> caixa e operador). Ver o passo 5.',
        N'-- dbgemco.dbo.FIKON_CAD_CAIXA (filial + serie da nota -> caixa e operador). Ver o passo 5.' + NCHAR(13) + NCHAR(10)
      + N'-- script 36 (24/11/2026): CXA_LANCTO gravada com STATUS 2 (antes 0).');
    SET @d = STUFF(@d, CHARINDEX(N'CREATE', @d), 6, N'ALTER');
    EXEC sys.sp_executesql @d;

    PRINT 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO alterada (STATUS 2). Copia: SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP36.';
END
GO

-- confere: deve mostrar o trecho com "= 2"
SELECT SUBSTRING(d, CHARINDEX(N'@STATUS          =', d), 80) AS trecho_status
  FROM (SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO')) AS d) x;
GO

/* ------------------------------- Parte 2: lançamentos já gravados com STATUS 0 ------------------ */
-- Cupons da FIKON (NUMPED 999999, TIPOPED 1, caixa da FIKON_CAD_CAIXA) com nota ativa na MOV_SAIDA.
-- Os de nota cancelada já estão com STATUS 9 e não entram.

-- prévia
SELECT l.DATENT, l.CODFIL, l.SERIE, l.NUMNOT, l.NUMCXA, l.CODOPER, l.CODEVE, l.VALLAN, l.STATUS
  FROM dbo.CXA_LANCTO l
 WHERE l.NUMPED = 999999 AND l.TIPOPED = 1 AND l.STATUS = 0
   AND EXISTS (SELECT 1 FROM dbo.FIKON_CAD_CAIXA c WHERE c.CODFIL = l.CODFIL AND c.SERIE = l.SERIE)
   AND EXISTS (SELECT 1 FROM dbo.MOV_SAIDA s
                WHERE s.CODFIL = l.CODFIL AND s.TPNOTA = l.TPNOTA AND s.NUMNOTA = l.NUMNOT
                  AND s.SERIE = l.SERIE AND s.DTNOTA = l.DATENT AND ISNULL(s.STATUS, 0) <> 9)
 ORDER BY l.DATENT, l.SERIE, l.NUMNOT;

BEGIN TRAN;

UPDATE l
   SET l.STATUS = 2
  FROM dbo.CXA_LANCTO l
 WHERE l.NUMPED = 999999 AND l.TIPOPED = 1 AND l.STATUS = 0
   AND EXISTS (SELECT 1 FROM dbo.FIKON_CAD_CAIXA c WHERE c.CODFIL = l.CODFIL AND c.SERIE = l.SERIE)
   AND EXISTS (SELECT 1 FROM dbo.MOV_SAIDA s
                WHERE s.CODFIL = l.CODFIL AND s.TPNOTA = l.TPNOTA AND s.NUMNOTA = l.NUMNOT
                  AND s.SERIE = l.SERIE AND s.DTNOTA = l.DATENT AND ISNULL(s.STATUS, 0) <> 9);

PRINT CONCAT('Lancamentos de cupom FIKON passados de STATUS 0 para 2: ', @@ROWCOUNT);

COMMIT;
GO
