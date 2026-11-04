/*
  01 - Ajuste da dbo.SP_FIKON_CANCELAR_NOTA  (Integrador Fikon)  -  04/11/2026

  O que muda (só estes 3 pontos; o resto da procedure fica igual):
    1. Recusa @chave vazia ou diferente de 44 caracteres.
       Hoje, com @chave = '' a procedure cancela TODAS as notas da MOV_SAIDA com CHAVENFE vazia
       e mexe no estoque de todas elas.
    2. Se já existir a entrada de cancelamento (ENT_NOTA serie 'CAN') com o mesmo número,
       a procedure passa a dar erro e desfazer tudo. Hoje ela pula o cancelamento da MOV_SAIDA
       mas continua mexendo no estoque e na MOV_ITPED (cancelamento pela metade).
    3. DTPROC do MOV_EXTRATOPROD: troca a data fixa '08/18/2026' pela data do dia.

  NÃO muda o depósito (@tpdep/@local): a baixa do faturamento (SP_FIKON_INTEGRA_MOV_ITSAIDA)
  é sempre no depósito 'L', e o cancelamento hoje também estorna em 'L'. Mexer só no
  cancelamento deixaria os dois lados diferentes.

  Como funciona: lê a definição atual, confere que cada trecho a trocar existe na quantidade
  esperada, guarda uma cópia como dbo.SP_FIKON_CANCELAR_NOTA_BKP_20261104 e aplica o ALTER.
  Se qualquer conferência falhar, nada é alterado.
  Conferido em 04/11/2026 contra o dev (DB-TREINO) e a Réplica (SQL-REPL): os trechos batem.

  Para voltar atrás: copiar o texto da _BKP_20261104, trocar o nome para SP_FIKON_CANCELAR_NOTA
  e executar como ALTER.
*/
SET XACT_ABORT ON;
SET NOCOUNT ON;

DECLARE @def  nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA'));
DECLARE @novo nvarchar(max);
DECLARE @bkp  nvarchar(max);
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);

IF @def IS NULL
BEGIN
    RAISERROR('dbo.SP_FIKON_CANCELAR_NOTA nao encontrada nesta base.', 16, 1);
    RETURN;
END;

IF @def LIKE N'%Chave de acesso invalida ou vazia%'
BEGIN
    RAISERROR('O ajuste ja foi aplicado nesta base. Nada a fazer.', 16, 1);
    RETURN;
END;

DECLARE @trechos TABLE (id int, velho nvarchar(400), novo nvarchar(1000), esperado int);

INSERT INTO @trechos (id, velho, novo, esperado) VALUES
-- 1. valida a chave antes de abrir a transação
(1,
 N'@horacancelamento time' + @crlf + @crlf + N'as' + @crlf + @crlf + N'BEGIN TRY',
 N'@horacancelamento time' + @crlf + @crlf + N'as' + @crlf + @crlf
   + N'-- Chave obrigatoria: com chave vazia o cursor pegaria todas as notas sem CHAVENFE.' + @crlf
   + N'IF LEN(LTRIM(RTRIM(ISNULL(@chave, '''')))) <> 44' + @crlf
   + N'BEGIN' + @crlf
   + N'    RAISERROR(''Chave de acesso invalida ou vazia: cancelamento nao realizado.'', 16, 1);' + @crlf
   + N'    RETURN;' + @crlf
   + N'END' + @crlf + @crlf
   + N'BEGIN TRY',
 1),
-- 2. entrada CAN já existente: erro (vai para o CATCH, que desfaz a transação)
(2,
 N'select ''J' + NCHAR(225) + N' Existe uma nota de entrada''',
 N'RAISERROR(''Ja existe entrada de cancelamento (serie CAN) com este numero de nota: cancelamento nao realizado.'', 16, 1)',
 1),
-- 3. DTPROC com a data do dia
(3,
 N'''08/18/2026''',
 N'CONVERT(date, GETDATE())',
 2);

-- Confere cada trecho antes de trocar qualquer coisa
DECLARE @erro nvarchar(400) =
(
    SELECT TOP (1) CONCAT('Trecho ', id, ': esperado ', esperado, ' ocorrencia(s), encontrado ',
                          (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, velho, N''))) / DATALENGTH(velho),
                          '. A procedure mudou; nada foi alterado.')
    FROM @trechos
    WHERE (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, velho, N''))) / DATALENGTH(velho) <> esperado
    ORDER BY id
);

IF @erro IS NOT NULL
BEGIN
    RAISERROR(@erro, 16, 1);
    RETURN;
END;

SET @novo = @def;
DECLARE @i int = 1, @velho nvarchar(400), @troca nvarchar(1000);
WHILE @i <= 3
BEGIN
    SELECT @velho = velho, @troca = novo FROM @trechos WHERE id = @i;
    SET @novo = REPLACE(@novo, @velho, @troca);
    SET @i += 1;
END;

-- CREATE -> ALTER
IF (DATALENGTH(@novo) - DATALENGTH(REPLACE(@novo, N'CREATE proc [dbo].[SP_FIKON_CANCELAR_NOTA]', N'')))
   / DATALENGTH(N'CREATE proc [dbo].[SP_FIKON_CANCELAR_NOTA]') <> 1
BEGIN
    RAISERROR('Cabecalho CREATE proc [dbo].[SP_FIKON_CANCELAR_NOTA] nao encontrado. Nada foi alterado.', 16, 1);
    RETURN;
END;

SET @bkp  = REPLACE(@def,  N'CREATE proc [dbo].[SP_FIKON_CANCELAR_NOTA]', N'CREATE proc [dbo].[SP_FIKON_CANCELAR_NOTA_BKP_20261104]');
SET @novo = REPLACE(@novo, N'CREATE proc [dbo].[SP_FIKON_CANCELAR_NOTA]', N'ALTER proc [dbo].[SP_FIKON_CANCELAR_NOTA]');

BEGIN TRAN;

    IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_20261104') IS NULL
        EXEC sys.sp_executesql @bkp;

    EXEC sys.sp_executesql @novo;

COMMIT;

PRINT 'SP_FIKON_CANCELAR_NOTA ajustada. Copia anterior em dbo.SP_FIKON_CANCELAR_NOTA_BKP_20261104.';

-- Conferência rápida (não altera nada): deve dar erro de chave invalida.
-- EXEC dbo.SP_FIKON_CANCELAR_NOTA @chave = '', @dtcancelamento = '2026-11-04', @horacancelamento = '00:00';
