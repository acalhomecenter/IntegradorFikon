/*
  35 - SP_FIKON_ENFILEIRAR_CLIENTE: põe o cliente na fila de cadastro da FIKON  -  24/11/2026
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  IMPORTANTE: rodar ANTES de publicar a ApiAcal que chama esta procedure (garantirClienteFikon).

  Problema:
    O pedido do app é enviado à FIKON só com o código do cliente ("C" + CODCLI). Quando o cliente ainda não foi
    cadastrado na FIKON (a fila FIKON_CAD_CLIENTE é processada pelo IntegradorFikon a cada minuto), a FIKON cria um
    cadastro provisório "Não obtido" sem CPF e sem endereço, e o pedido falha por falta de UF da pessoa.

  O que muda:
    A ApiAcal, antes de enviar o pedido, consulta o cliente na FIKON. Se não existir, chama esta procedure e responde
    ao app "Cliente não integrado, aguarde 1 min e em seguida tente novamente" (o pedido não é enviado).
    Esta procedure:
      1. Confere se o cliente existe na CAD_CLIENTE (senão, RAISERROR e nada é gravado).
      2. Insere na FIKON_CAD_CLIENTE uma linha TIPO 'I' / STATUS 'P', só se ainda não houver linha 'P' do cliente.
      3. Insere na FIKON_CAD_END_CLIENTE uma linha TIPO 'I' / STATUS 'P' por endereço da CAD_ENDCLI, só para os
         endereços que ainda não têm linha 'P'.
    Tudo numa transação, com UPDLOCK/HOLDLOCK: duas chamadas ao mesmo tempo (dois pedidos do mesmo cliente) não
    duplicam a fila. Chamar de novo enquanto a fila está pendente não faz nada.
    Os dados do cliente continuam saindo da SP_FIKON_INSERT_CLIENTE, como no fluxo normal.

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
  Para voltar atrás: DROP PROCEDURE dbo.SP_FIKON_ENFILEIRAR_CLIENTE (a ApiAcal passa a responder erro no
  pedido de cliente que não está na FIKON, em vez de enfileirar).
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.SP_FIKON_ENFILEIRAR_CLIENTE', 'P') IS NULL
    EXEC ('CREATE PROCEDURE dbo.SP_FIKON_ENFILEIRAR_CLIENTE AS RETURN 0');
GO

ALTER PROCEDURE dbo.SP_FIKON_ENFILEIRAR_CLIENTE
    @codcli numeric(12,0)
AS
/* script 35 - põe o cliente na fila FIKON_CAD_CLIENTE / FIKON_CAD_END_CLIENTE (chamada pela ApiAcal) */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @codcli IS NULL OR @codcli <= 0
    BEGIN
        RAISERROR('Código de cliente inválido para a fila da FIKON.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.CAD_CLIENTE WHERE CODCLI = @codcli)
    BEGIN
        DECLARE @codtexto varchar(20) = CAST(@codcli AS varchar(20));
        RAISERROR('Cliente %s não existe no Gemco (CAD_CLIENTE).', 16, 1, @codtexto);
        RETURN;
    END

    DECLARE @agora datetime = GETDATE();

    BEGIN TRAN;

        -- Cliente: uma linha pendente por vez.
        IF NOT EXISTS (SELECT 1
                         FROM dbo.FIKON_CAD_CLIENTE WITH (UPDLOCK, HOLDLOCK)
                        WHERE CODCLI = @codcli AND STATUS = 'P')
        BEGIN
            INSERT INTO dbo.FIKON_CAD_CLIENTE (CODCLI, DTINCLUSAO, TIPO, STATUS)
            VALUES (@codcli, @agora, 'I', 'P');
        END

        -- Endereços: uma linha pendente por endereço da CAD_ENDCLI.
        INSERT INTO dbo.FIKON_CAD_END_CLIENTE (CODCLI, DTINCLUSAO, TIPO, STATUS, CODEND)
        SELECT e.CODCLI, @agora, 'I', 'P', e.CODEND
          FROM dbo.CAD_ENDCLI e
         WHERE e.CODCLI = @codcli
           AND NOT EXISTS (SELECT 1
                             FROM dbo.FIKON_CAD_END_CLIENTE f WITH (UPDLOCK, HOLDLOCK)
                            WHERE f.CODCLI = e.CODCLI AND f.CODEND = e.CODEND AND f.STATUS = 'P');

    COMMIT;
END
GO

/* ===================== Opcional: índices da fila =====================
   A procedure procura por CODCLI + STATUS. Sem índice ela lê a tabela inteira (rápido enquanto a fila for
   pequena). Se a FIKON_CAD_CLIENTE / FIKON_CAD_END_CLIENTE já tiverem muitas linhas, rode este bloco.

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FIKON_CAD_CLIENTE_CODCLI_STATUS')
    CREATE NONCLUSTERED INDEX IX_FIKON_CAD_CLIENTE_CODCLI_STATUS ON dbo.FIKON_CAD_CLIENTE (CODCLI, STATUS);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FIKON_CAD_END_CLIENTE_CODCLI_STATUS')
    CREATE NONCLUSTERED INDEX IX_FIKON_CAD_END_CLIENTE_CODCLI_STATUS ON dbo.FIKON_CAD_END_CLIENTE (CODCLI, STATUS, CODEND);
*/

/* ===================== Conferência (só leitura) =====================
   Troque 501547 pelo cliente testado. Depois de EXEC dbo.SP_FIKON_ENFILEIRAR_CLIENTE 501547, deve aparecer
   uma linha 'P' na FIKON_CAD_CLIENTE e uma por endereço na FIKON_CAD_END_CLIENTE; rodar de novo não duplica.

SELECT 'CLIENTE' AS fila, ID, CODCLI, NULL AS CODEND, TIPO, STATUS, DTINCLUSAO, DTINTEGRACAO, RETORNO
  FROM dbo.FIKON_CAD_CLIENTE WHERE CODCLI = 501547
UNION ALL
SELECT 'ENDERECO', ID, CODCLI, CODEND, TIPO, STATUS, DTINCLUSAO, DTINTEGRACAO, CAST(RETORNO AS varchar(200))
  FROM dbo.FIKON_CAD_END_CLIENTE WHERE CODCLI = 501547
 ORDER BY fila, ID;
*/
