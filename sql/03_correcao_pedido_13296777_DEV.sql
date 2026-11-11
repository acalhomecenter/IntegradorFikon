/*
  03 - Correção da nota 72 série 444 do pedido Gemco 13296777 (FIKON 672108)  -  SOMENTE DEV (DB-TREINO)  -  10/11/2026

  Situação encontrada (10/11/2026, filial 15, TPNOTA 251):
    - 10:36:25  nota 72 série U01 gravada (faturamento).
    - 10:39:48  nota 72 cancelada: U01 com STATUS 9 e entrada CAN 72 gerada (ENT_NOTA/ENT_ITENT).
    - 10:40:04  a mesma nota 72, com a MESMA chave, foi gravada de novo como série 444, ativa.
                Foi um segundo IntegradorFikon (código antigo) rodando contra o dev.
    - O webhook de cancelamento passou a falhar com ENT_ITENT_PK: a procedure acha a 444 pela chave,
      vê que a entrada CAN 72 já existe, pula o cabeçalho e tenta inserir o item de novo.
    - Hoje: 72/444 ativa; MOV_ITPED item 1 (18247) com QTFAT 1 / QTLIB 0 / STATUS 6;
      MOV_PEDIDO STATUS 6; FIKON_INTEGRACAO_PEDIDO = 'FATURADO'.

  O que este script faz (o mesmo tratamento do script 02):
    - MOV_SAIDA e MOV_ITSAIDA da 72/444 -> STATUS 9, STATUSNFE 9, DTCANCEL hoje;
    - estorna a baixa: SPU_PROLOCI com +QTCOMP no FISICO e no RESFIS, depósito 'L'
      (o inverso exato do que a SP_FIKON_INTEGRA_MOV_ITSAIDA fez);
    - MOV_ITPED: QTFAT - QTCOMP, QTLIB + QTCOMP, STATUS 5;
    - MOV_PEDIDO STATUS 5 e FIKON_INTEGRACAO_PEDIDO = 'LIBERADO CXA', para o integrador corrigido
      integrar a nota válida quando a FIKON refaturar.

  Não gera entrada CAN para a 444: a entrada CAN 72 já existe (da U01) e a 444 nunca deveria
  ter existido no Gemco.

  Depois deste script, o reenvio do webhook de cancelamento da nota 72 não acha nota ativa com essa
  chave; a ApiAcal corrigida responde "Nota já estava cancelada no Gemco" e a FIKON para de reenviar.

  IMPORTANTE
    - Pare ANTES os dois IntegradorFikon que estão apontando para o dev (NB-TI-JEFFERSON e
      TI-LUAN-COSTA, ambos com código antigo) e publique uma única instância com a versão corrigida
      (branch fix/faturamento-notas-canceladas). Com o código antigo, ao voltar para 'LIBERADO CXA'
      o pedido é reprocessado e a nota cancelada é reenviada.
    - O script termina com ROLLBACK. Confira os SELECTs do final e, se estiver certo,
      troque o ROLLBACK por COMMIT e rode de novo.
*/
SET XACT_ABORT ON;
SET NOCOUNT ON;

IF @@SERVERNAME <> 'DB-TREINO' OR DB_NAME() <> 'dbgemco'
BEGIN
    RAISERROR('Este script e so para o dbgemco do DB-TREINO (dev).', 16, 1);
    RETURN;
END;

DECLARE @numpedven numeric(12) = 13296777;
DECLARE @codfil    int         = 15;
DECLARE @tpnota    numeric(3)  = 251;
DECLARE @dtnota    date        = '2026-11-10';
DECLARE @numnota   numeric(12) = 72;
DECLARE @serie     varchar(3)  = '444';
DECLARE @hoje      date        = CONVERT(date, GETDATE());

BEGIN TRAN;

    -- Conferência: a 72/444 tem de estar ativa e a 72/U01 já cancelada.
    IF (SELECT COUNT(*) FROM MOV_SAIDA
         WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota AND NUMPEDVEN = @numpedven
           AND NUMNOTA = @numnota AND SERIE = @serie AND STATUS <> 9) <> 1
       OR
       (SELECT COUNT(*) FROM MOV_SAIDA
         WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota AND NUMPEDVEN = @numpedven
           AND NUMNOTA = @numnota AND SERIE = 'U01' AND STATUS = 9) <> 1
    BEGIN
        RAISERROR('A nota 72/444 nao esta ativa ou a 72/U01 nao esta cancelada. Dados mudaram; nada foi feito.', 16, 1);
        ROLLBACK;
        RETURN;
    END;

    -- Itens da nota errada (antes de cancelar)
    DECLARE @itens TABLE (coditprod numeric(9), item int, qtcomp numeric(12,3));
    INSERT INTO @itens
    SELECT CODITPROD, ITEM, QTCOMP
      FROM MOV_ITSAIDA
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota
       AND NUMNOTA = @numnota AND SERIE = @serie AND STATUS <> 9;

    -- 1. Estorno de estoque (inverso da baixa da SP_FIKON_INTEGRA_MOV_ITSAIDA) e item do pedido liberado
    DECLARE @coditprod numeric(9), @item int, @qt numeric(12,3);
    DECLARE cr CURSOR LOCAL FAST_FORWARD FOR SELECT coditprod, item, qtcomp FROM @itens;
    OPEN cr;
    FETCH NEXT FROM cr INTO @coditprod, @item, @qt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC SPU_PROLOCI 1, @codfil, 'L', @coditprod, @qt, @qt, 0, 0, 0, 0, 0, 0, 0, NULL, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0;

        UPDATE MOV_ITPED WITH (READCOMMITTED)
           SET QTFAT = QTFAT - @qt, QTLIB = QTLIB + @qt, STATUS = 5, SITCARGA = 0
         WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven
           AND CODITPROD = @coditprod AND ITEM = @item;

        FETCH NEXT FROM cr INTO @coditprod, @item, @qt;
    END;
    CLOSE cr;
    DEALLOCATE cr;

    -- 2. Cancela a 72/444
    UPDATE MOV_ITSAIDA WITH (READCOMMITTED)
       SET STATUS = 9
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota
       AND NUMNOTA = @numnota AND SERIE = @serie AND STATUS <> 9;

    UPDATE MOV_SAIDA WITH (READCOMMITTED)
       SET STATUS = 9, STATUSNFE = 9, DTCANCEL = @hoje, NUMORC = NULL
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota AND NUMPEDVEN = @numpedven
       AND NUMNOTA = @numnota AND SERIE = @serie AND STATUS <> 9;

    -- 3. Pedido volta para a fila do integrador
    UPDATE MOV_PEDIDO WITH (READCOMMITTED)
       SET STATUS = 5, SITCARGA = 0, FLBXESTOQUE = NULL
     WHERE CODFIL = @codfil AND NUMPEDVEN = @numpedven;

    UPDATE FIKON_INTEGRACAO_PEDIDO
       SET STATUS = 'LIBERADO CXA'
     WHERE pedido_gemco = @numpedven;

    -- Conferência (esperado: 72/U01 e 72/444 com STATUS 9; QTFAT 0 e QTLIB 1; FISICO e RESFIS +1; LIBERADO CXA)
    SELECT 'MOV_SAIDA' AS tabela, NUMNOTA, SERIE, STATUS, STATUSNFE, DTCANCEL, CHAVENFE
      FROM MOV_SAIDA WHERE NUMPEDVEN = @numpedven ORDER BY DATAHORAUTC;
    SELECT 'MOV_ITSAIDA' AS tabela, NUMNOTA, SERIE, CODITPROD, ITEM, QTCOMP, STATUS
      FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota AND NUMNOTA = @numnota;
    SELECT 'MOV_ITPED' AS tabela, CODITPROD, ITEM, QTCOMP, QTFAT, QTLIB, STATUS
      FROM MOV_ITPED WHERE NUMPEDVEN = @numpedven;
    SELECT 'MOV_PEDIDO' AS tabela, STATUS, SITCARGA
      FROM MOV_PEDIDO WHERE CODFIL = @codfil AND NUMPEDVEN = @numpedven;
    SELECT 'ESTOQUE' AS tabela, l.CODITPROD, l.TPDEPOS, l.FISICO, l.RESFIS   -- antes: FISICO 17, RESFIS 9
      FROM CAD_PRODLOC l JOIN @itens i ON i.coditprod = l.CODITPROD
     WHERE l.CODFIL = @codfil AND l.TPDEPOS = 'L';
    SELECT 'INTEGRACAO' AS tabela, pedido_gemco, pedido_fikon, STATUS
      FROM FIKON_INTEGRACAO_PEDIDO WHERE pedido_gemco = @numpedven;

ROLLBACK;   -- conferiu e está certo? troque por COMMIT e rode de novo.
