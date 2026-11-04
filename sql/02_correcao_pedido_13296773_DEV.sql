/*
  02 - Correção dos dados do pedido Gemco 13296773 (FIKON 660484)  -  SOMENTE DEV (DB-TREINO)  -  04/11/2026

  Situação encontrada (03/11/2026, filial 15, TPNOTA 251):
    - nota 70 serie U01 : cancelada corretamente (STATUS 9, entrada CAN 70 gerada).
    - nota 70 serie 444 : ATIVA, com a chave da nota 70 cancelada  -> errada.
    - nota 18 serie 001 : ATIVA, sem chave; cancelada na FIKON      -> errada.
    - nota 71            : não existe no Gemco (é a nota válida na FIKON).
    - MOV_ITPED item 1 (18247): QTCOMP 1, QTFAT 2, QTLIB -1  (faturou 2 vezes a mais).
    - Estoque: as duas notas erradas deram baixa de 1 no FISICO e 1 no RESFIS cada (depósito 'L').

  O que este script faz, para cada nota errada (70/444 e 18/001):
    - MOV_SAIDA e MOV_ITSAIDA -> STATUS 9 (cancelada), STATUSNFE 9, DTCANCEL hoje;
    - estorna a baixa: SPU_PROLOCI com +QTCOMP no FISICO e no RESFIS, depósito 'L'
      (o inverso exato do que a SP_FIKON_INTEGRA_MOV_ITSAIDA fez);
    - MOV_ITPED: QTFAT - QTCOMP, QTLIB + QTCOMP, STATUS 5 (mesmo tratamento da SP_FIKON_CANCELAR_NOTA).
  Depois: MOV_PEDIDO STATUS 5 e FIKON_INTEGRACAO_PEDIDO = 'LIBERADO CXA', para o integrador
  (já com a correção do FikonRepositorio.cs) integrar a nota 71.

  Não gera ENT_NOTA 'CAN' para essas duas notas: elas nunca deveriam ter existido no Gemco.

  IMPORTANTE
    - Rode só depois de publicar o integrador corrigido no dev, ou com o serviço parado.
      Com o código antigo, ao voltar para 'LIBERADO CXA' ele reenvia as notas canceladas.
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

DECLARE @numpedven numeric(12) = 13296773;
DECLARE @codfil    int         = 15;
DECLARE @tpnota    numeric(3)  = 251;
DECLARE @dtnota    date        = '2026-11-03';
DECLARE @hoje      date        = CONVERT(date, GETDATE());

DECLARE @notas TABLE (numnota numeric(12), serie varchar(3));
INSERT INTO @notas VALUES (70, '444'), (18, '001');

BEGIN TRAN;

    -- Conferência: as duas notas erradas têm de estar ativas, uma vez cada.
    IF (SELECT COUNT(*)
          FROM MOV_SAIDA s
          JOIN @notas n ON n.numnota = s.NUMNOTA AND n.serie = s.SERIE
         WHERE s.CODFIL = @codfil AND s.TPNOTA = @tpnota AND s.DTNOTA = @dtnota
           AND s.NUMPEDVEN = @numpedven AND s.STATUS <> 9) <> 2
    BEGIN
        RAISERROR('As notas 70/444 e 18/001 nao estao as duas ativas. Dados mudaram; nada foi feito.', 16, 1);
        ROLLBACK;
        RETURN;
    END;

    -- Itens das notas erradas (antes de cancelar)
    DECLARE @itens TABLE (numnota numeric(12), serie varchar(3), coditprod numeric(9), item int, qtcomp numeric(12,3));
    INSERT INTO @itens
    SELECT i.NUMNOTA, i.SERIE, i.CODITPROD, i.ITEM, i.QTCOMP
      FROM MOV_ITSAIDA i
      JOIN @notas n ON n.numnota = i.NUMNOTA AND n.serie = i.SERIE
     WHERE i.CODFIL = @codfil AND i.TPNOTA = @tpnota AND i.DTNOTA = @dtnota AND i.STATUS <> 9;

    -- 1. Estorno de estoque (inverso da baixa da SP_FIKON_INTEGRA_MOV_ITSAIDA)
    DECLARE @coditprod numeric(9), @item int, @qt numeric(12,3);
    DECLARE cr CURSOR LOCAL FAST_FORWARD FOR SELECT coditprod, item, qtcomp FROM @itens;
    OPEN cr;
    FETCH NEXT FROM cr INTO @coditprod, @item, @qt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC SPU_PROLOCI 1, @codfil, 'L', @coditprod, @qt, @qt, 0, 0, 0, 0, 0, 0, 0, NULL, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0;

        -- 2. Item do pedido volta a ficar liberado
        UPDATE MOV_ITPED WITH (READCOMMITTED)
           SET QTFAT = QTFAT - @qt, QTLIB = QTLIB + @qt, STATUS = 5, SITCARGA = 0
         WHERE CODFIL = @codfil AND TIPOPED = 0 AND NUMPEDVEN = @numpedven
           AND CODITPROD = @coditprod AND ITEM = @item;

        FETCH NEXT FROM cr INTO @coditprod, @item, @qt;
    END;
    CLOSE cr;
    DEALLOCATE cr;

    -- 3. Cancela as duas notas erradas
    UPDATE i WITH (READCOMMITTED)
       SET STATUS = 9
      FROM MOV_ITSAIDA i
      JOIN @notas n ON n.numnota = i.NUMNOTA AND n.serie = i.SERIE
     WHERE i.CODFIL = @codfil AND i.TPNOTA = @tpnota AND i.DTNOTA = @dtnota AND i.STATUS <> 9;

    UPDATE s WITH (READCOMMITTED)
       SET STATUS = 9, STATUSNFE = 9, DTCANCEL = @hoje, NUMORC = NULL
      FROM MOV_SAIDA s
      JOIN @notas n ON n.numnota = s.NUMNOTA AND n.serie = s.SERIE
     WHERE s.CODFIL = @codfil AND s.TPNOTA = @tpnota AND s.DTNOTA = @dtnota
       AND s.NUMPEDVEN = @numpedven AND s.STATUS <> 9;

    -- 4. Pedido volta para a fila do integrador
    UPDATE MOV_PEDIDO WITH (READCOMMITTED)
       SET STATUS = 5, SITCARGA = 0, FLBXESTOQUE = NULL
     WHERE CODFIL = @codfil AND NUMPEDVEN = @numpedven;

    UPDATE FIKON_INTEGRACAO_PEDIDO
       SET STATUS = 'LIBERADO CXA'
     WHERE pedido_gemco = @numpedven;

    -- Conferência (esperado: 70/U01, 70/444 e 18/001 com STATUS 9; QTFAT 0 e QTLIB 1; LIBERADO CXA)
    SELECT 'MOV_SAIDA' AS tabela, NUMNOTA, SERIE, STATUS, STATUSNFE, DTCANCEL, CHAVENFE
      FROM MOV_SAIDA WHERE NUMPEDVEN = @numpedven ORDER BY HRHORA, SERIE;
    SELECT 'MOV_ITSAIDA' AS tabela, NUMNOTA, SERIE, CODITPROD, ITEM, QTCOMP, STATUS
      FROM MOV_ITSAIDA WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND DTNOTA = @dtnota AND NUMNOTA IN (70, 18);
    SELECT 'MOV_ITPED' AS tabela, CODITPROD, ITEM, QTCOMP, QTFAT, QTLIB, STATUS
      FROM MOV_ITPED WHERE NUMPEDVEN = @numpedven;
    SELECT 'ESTOQUE' AS tabela, l.CODITPROD, l.TPDEPOS, l.FISICO, l.RESFIS
      FROM CAD_PRODLOC l JOIN @itens i ON i.coditprod = l.CODITPROD
     WHERE l.CODFIL = @codfil AND l.TPDEPOS = 'L';
    SELECT 'INTEGRACAO' AS tabela, pedido_gemco, pedido_fikon, STATUS
      FROM FIKON_INTEGRACAO_PEDIDO WHERE pedido_gemco = @numpedven;

ROLLBACK;   -- conferiu e está certo? troque por COMMIT e rode de novo.
