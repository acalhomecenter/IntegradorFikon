/*
  01 - Ajuste da dbo.SP_FIKON_CANCELAR_NOTA  (Integrador Fikon / ApiAcal)  -  04/11/2026

  Chamada pela ApiAcal (webhook CANCELAMENTO da FIKON, PedidoFikonRepositprio.cancelarNotaGemco).

  O que muda (o resto da procedure fica igual):
    1. Dois parâmetros novos, opcionais: @codfil_nota e @numnota_nota.
       - Com chave válida (44 caracteres): cancela pela chave, como hoje (os novos são ignorados).
       - Sem chave: cancela a nota da filial/número que está SEM chave na MOV_SAIDA.
         Se houver mais de uma nessa situação, recusa (nota ambígua).
       - Sem chave e sem filial/número: recusa. Hoje, com @chave = '' a procedure cancela TODAS
         as notas da MOV_SAIDA com CHAVENFE vazia e mexe no estoque de todas elas.
    2. Se já existir a entrada de cancelamento (ENT_NOTA serie 'CAN') com o mesmo número,
       dá erro e desfaz tudo. Hoje ela pula o cancelamento da MOV_SAIDA mas continua mexendo
       no estoque e na MOV_ITPED (cancelamento pela metade).
    3. DTPROC do MOV_EXTRATOPROD: troca a data fixa '08/18/2026' pela data do dia.

  Chamadas atuais (só @chave, @dtcancelamento, @horacancelamento) continuam funcionando.

  NÃO muda o depósito (@tpdep/@local): a baixa do faturamento (SP_FIKON_INTEGRA_MOV_ITSAIDA)
  é sempre no depósito 'L', e o cancelamento hoje também estorna em 'L'.

  Como funciona: lê a definição atual, confere que cada trecho a trocar existe na quantidade
  esperada, guarda uma cópia como dbo.SP_FIKON_CANCELAR_NOTA_BKP_20261104 e aplica o ALTER.
  Se qualquer conferência falhar, nada é alterado.
  Trechos conferidos em 04/11/2026 no dev (DB-TREINO) e na Réplica (SQL-REPL).

  Para voltar atrás: copiar o texto da _BKP_20261104, trocar o nome para SP_FIKON_CANCELAR_NOTA
  e executar como ALTER. Atenção: a ApiAcal corrigida passa a mandar @codfil_nota/@numnota_nota
  quando não há chave; a versão antiga não aceita esses parâmetros.
*/
SET XACT_ABORT ON;
SET NOCOUNT ON;

DECLARE @def  nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA'));
DECLARE @novo nvarchar(max);
DECLARE @bkp  nvarchar(max);
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @lf   nchar(1) = NCHAR(10);

IF @def IS NULL
BEGIN
    RAISERROR('dbo.SP_FIKON_CANCELAR_NOTA nao encontrada nesta base.', 16, 1);
    RETURN;
END;

IF @def LIKE N'%@numnota_nota%'
BEGIN
    RAISERROR('O ajuste ja foi aplicado nesta base. Nada a fazer.', 16, 1);
    RETURN;
END;

DECLARE @trechos TABLE (id int, velho nvarchar(400), novo nvarchar(4000), esperado int);

INSERT INTO @trechos (id, velho, novo, esperado) VALUES
-- 1. parâmetros novos + validação da chave / nota sem chave, antes de abrir a transação
(1,
 N'@horacancelamento time' + @crlf + @crlf + N'as' + @crlf + @crlf + N'BEGIN TRY',
 N'@horacancelamento time,' + @crlf
   + N'@codfil_nota int = NULL,           -- filial Gemco da nota (so para nota sem chave)' + @crlf
   + N'@numnota_nota numeric(12) = NULL   -- numero da nota (so para nota sem chave)' + @crlf + @crlf
   + N'as' + @crlf + @crlf
   + N'IF LEN(LTRIM(RTRIM(ISNULL(@chave, '''')))) = 44' + @crlf
   + N'BEGIN' + @crlf
   + N'    -- Com chave valida, cancela pela chave (caminho normal).' + @crlf
   + N'    SET @codfil_nota = NULL;' + @crlf
   + N'    SET @numnota_nota = NULL;' + @crlf
   + N'END' + @crlf
   + N'ELSE' + @crlf
   + N'BEGIN' + @crlf
   + N'    -- Sem chave: so cancela a nota SEM chave daquela filial/numero, e so se for unica.' + @crlf
   + N'    -- Nunca cancelar por chave vazia: pegaria todas as notas sem CHAVENFE.' + @crlf
   + N'    IF @codfil_nota IS NULL OR @numnota_nota IS NULL' + @crlf
   + N'    BEGIN' + @crlf
   + N'        RAISERROR(''Chave de acesso invalida ou vazia e filial/numero da nota nao informados: cancelamento nao realizado.'', 16, 1);' + @crlf
   + N'        RETURN;' + @crlf
   + N'    END' + @crlf + @crlf
   + N'    SET @chave = '''';' + @crlf + @crlf
   + N'    IF (SELECT COUNT(*) FROM MOV_SAIDA' + @crlf
   + N'         WHERE CHAVENFE = '''' AND CODFIL = @codfil_nota AND NUMNOTA = @numnota_nota AND STATUS <> 9) > 1' + @crlf
   + N'    BEGIN' + @crlf
   + N'        RAISERROR(''Mais de uma nota ativa sem chave com esta filial/numero: cancelamento nao realizado.'', 16, 1);' + @crlf
   + N'        RETURN;' + @crlf
   + N'    END' + @crlf
   + N'END' + @crlf + @crlf
   + N'BEGIN TRY',
 1),
-- 2. cursor: pela chave; sem chave, restringe a filial/numero
(2,
 N'WHERE CHAVENFE = @chave' + @lf + N'  AND STATUS <> 9;',
 N'WHERE CHAVENFE = @chave' + @lf
   + N'  AND STATUS <> 9' + @lf
   + N'  AND (@numnota_nota IS NULL OR (CODFIL = @codfil_nota AND NUMNOTA = @numnota_nota));',
 1),
-- 3. entrada CAN já existente: erro (vai para o CATCH, que desfaz a transação)
(3,
 N'select ''J' + NCHAR(225) + N' Existe uma nota de entrada''',
 N'RAISERROR(''Ja existe entrada de cancelamento (serie CAN) com este numero de nota: cancelamento nao realizado.'', 16, 1)',
 1),
-- 4. DTPROC com a data do dia
(4,
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
DECLARE @i int = 1, @velho nvarchar(400), @troca nvarchar(4000);
WHILE @i <= 4
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

-- Conferência rápida (não altera nada): as duas devem dar erro.
-- EXEC dbo.SP_FIKON_CANCELAR_NOTA @chave = '', @dtcancelamento = '2026-11-04', @horacancelamento = '00:00';
-- EXEC dbo.SP_FIKON_CANCELAR_NOTA @chave = NULL, @dtcancelamento = '2026-11-04', @horacancelamento = '00:00';
