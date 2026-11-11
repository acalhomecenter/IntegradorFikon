/*
  04 - Trava contra nota duplicada por chave de acesso na MOV_SAIDA  (Integrador Fikon / ApiAcal)  -  10/11/2026

  Procedures alteradas:
    - dbo.SP_FIKON_INTEGRA_MOV_SAIDA        (faturamento de pedido, chamada pelo IntegradorFikon)
    - dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA  (venda de cupom, chamada pela ApiAcal no webhook VENDA/PEDIDO)

  Problema que resolve
    Em 03/11 (nota 70) e 10/11 (notas 72 e 73), depois de um cancelamento a SP_FIKON_CANCELAR_NOTA
    devolve o pedido para 'LIBERADO CXA'. Segundos depois, um IntegradorFikon com código antigo reenviou
    a nota cancelada. Como havia duas instâncias gravando séries diferentes (U01 e 444), a chave primária
    da MOV_SAIDA (CODFIL, TPNOTA, NUMNOTA, SERIE, DTNOTA) não segurou e a nota cancelada voltou como
    uma nota nova, ativa, com a mesma CHAVENFE.

  O que muda (só isto; o resto das procedures fica igual)
    Logo no início, antes do BEGIN TRY: se a @chave tem 44 caracteres e já existe linha na MOV_SAIDA
    com essa CHAVENFE (ativa OU cancelada), a procedure recusa com erro e não grava nada.
      - Nota ativa com a mesma chave: já está integrada; nada a fazer.
      - Nota cancelada com a mesma chave: foi cancelada na FIKON; não pode voltar.
    O erro (e não um retorno silencioso) é de propósito: assim o chamador não marca o pedido como
    FATURADO por engano. O IntegradorFikon corrigido já não reenvia nota cancelada, então em uso normal
    a trava não dispara; ela protege contra versões antigas, instâncias duplicadas e webhooks repetidos.

  Limites
    - Nota sem chave (@chave vazia) não é verificada: não há como identificá-la pela chave.
    - A conferência é feita antes da gravação, sem lock. Duas gravações da MESMA chave no mesmo
      instante ainda podem passar; a proteção total exigiria um índice único filtrado em CHAVENFE,
      que é mudança de estrutura no Gemco (não incluída aqui).
    - A consulta usa o índice MOV_SAIDA_IDX_CHAVENFE (existe na produção).

  Como funciona: para cada procedure, lê a definição atual, confere que o cabeçalho CREATE e o BEGIN TRY
  existem uma única vez, guarda uma cópia como <nome>_BKP_20261110 e aplica o ALTER. Se qualquer
  conferência falhar, aquela procedure não é alterada. Tudo numa transação: ou as duas mudam, ou nenhuma.
  Conferido no dev (DB-TREINO) em 10/11/2026. Na produção, a própria conferência do script decide.

  Para voltar atrás: copiar o texto da <nome>_BKP_20261110, trocar o nome pelo original e executar como ALTER.
*/
SET XACT_ABORT ON;
SET NOCOUNT ON;

DECLARE @procs TABLE (id int, nome sysname);
INSERT INTO @procs VALUES (1, N'SP_FIKON_INTEGRA_MOV_SAIDA'), (2, N'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA');

DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);

DECLARE @trava nvarchar(max) =
      N'-- TRAVA_CHAVE_DUPLICADA (10/11/2026): nao grava nota cuja chave ja existe na MOV_SAIDA,' + @crlf
    + N'-- ativa ou cancelada. Evita recriar nota cancelada e duplicar nota ja integrada.' + @crlf
    + N'IF LEN(LTRIM(RTRIM(ISNULL(@chave, '''')))) = 44' + @crlf
    + N'   AND EXISTS (SELECT 1 FROM MOV_SAIDA WHERE CHAVENFE = LTRIM(RTRIM(@chave)))' + @crlf
    + N'BEGIN' + @crlf
    + N'    DECLARE @msg_trava varchar(300) = ''Nota com chave '' + LTRIM(RTRIM(@chave))' + @crlf
    + N'        + '' ja existe na MOV_SAIDA (ativa ou cancelada): gravacao recusada para evitar duplicidade.'';' + @crlf
    + N'    RAISERROR(@msg_trava, 16, 1);' + @crlf
    + N'    RETURN;' + @crlf
    + N'END' + @crlf + @crlf
    + N'BEGIN TRY';

DECLARE @i int = 1, @nome sysname, @def nvarchar(max), @novo nvarchar(max), @bkp nvarchar(max),
        @cab nvarchar(300), @erro nvarchar(400);

-- 1ª passada: confere tudo antes de alterar qualquer coisa
WHILE @i <= 2
BEGIN
    SELECT @nome = nome FROM @procs WHERE id = @i;
    SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @nome));
    SET @cab = N'CREATE proc [dbo].[' + @nome + N']';

    IF @def IS NULL
        SET @erro = @nome + N' nao encontrada nesta base.';
    ELSE IF @def LIKE N'%TRAVA_CHAVE_DUPLICADA%'
        SET @erro = @nome + N': a trava ja foi aplicada nesta base. Nada foi alterado.';
    ELSE IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, N'BEGIN TRY', N''))) / DATALENGTH(N'BEGIN TRY') <> 1
        SET @erro = @nome + N': esperado 1 BEGIN TRY. A procedure mudou; nada foi alterado.';
    ELSE IF (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @cab, N''))) / DATALENGTH(@cab) <> 1
        SET @erro = @nome + N': cabecalho "' + @cab + N'" nao encontrado. Nada foi alterado.';
    ELSE IF @def NOT LIKE N'%@chave varchar(44)%'
        SET @erro = @nome + N': parametro @chave varchar(44) nao encontrado. Nada foi alterado.';

    IF @erro IS NOT NULL
    BEGIN
        RAISERROR(@erro, 16, 1);
        RETURN;
    END;

    SET @i += 1;
END;

-- 2ª passada: aplica
BEGIN TRAN;

SET @i = 1;
WHILE @i <= 2
BEGIN
    SELECT @nome = nome FROM @procs WHERE id = @i;
    SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @nome));
    SET @cab = N'CREATE proc [dbo].[' + @nome + N']';

    SET @bkp  = REPLACE(@def, @cab, N'CREATE proc [dbo].[' + @nome + N'_BKP_20261110]');
    SET @novo = REPLACE(REPLACE(@def, N'BEGIN TRY', @trava), @cab, N'ALTER proc [dbo].[' + @nome + N']');

    IF OBJECT_ID(N'dbo.' + @nome + N'_BKP_20261110') IS NULL
        EXEC sys.sp_executesql @bkp;

    EXEC sys.sp_executesql @novo;

    PRINT @nome + N' ajustada. Copia anterior em dbo.' + @nome + N'_BKP_20261110.';
    SET @i += 1;
END;

COMMIT;

-- Conferência (depois de aplicar): deve listar as duas procedures com a trava.
SELECT o.name, o.modify_date FROM sys.objects o JOIN sys.sql_modules m ON m.object_id = o.object_id
 WHERE o.name IN ('SP_FIKON_INTEGRA_MOV_SAIDA', 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA')
   AND m.definition LIKE '%TRAVA_CHAVE_DUPLICADA%';
