/*
  19 - Restaura a chave de acesso da NFC-e 120 (filial 502, série U01) - PRODUÇÃO  -  16/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  O que aconteceu:
    A NFC-e 120 do pedido 14206602 (FIKON 2013678) foi gravada com a chave da FIKON
      23261107201916001716650010000001201073778518  (modelo 65, a mesma que o script 14 conferiu).
    Depois do script 14 a nota mudou dentro do Gemco: série '1' -> 'U01', STATUSNFE 3 -> 2, e ganhou
    NUMNFE 32187343 / DIGNFE 1 e uma chave NOVA, gerada pelo Gemco com modelo 55:
      23261107201916001716550010000001201321873431
    Nenhuma procedure da integração FIKON grava NUMNFE/DIGNFE; foi uma rotina/tela do Gemco. A nota não foi
    transmitida pelo Gemco (nada em NF_SAIDA, HST_NF_SAIDA, RETXML, PDV_MOV_SAIDA).
    Efeito: a devolução 27 da FIKON aponta para a chave verdadeira (modelo 65) e o Gemco não acha a nota:
      "Nota de saida (chave 23261107201916001716650010000001201073778518) nao encontrada no Gemco."

  O que o script faz (numa transação):
    1. Confere que a nota 120 está exatamente como acima e que nenhuma outra nota usa a chave da FIKON.
       Se algo estiver diferente, não altera nada.
    2. Volta a chave da FIKON, MODELONF 65 e STATUSNFE 3 (como o script 14 deixou), e limpa NUMNFE/DIGNFE.
       A série fica U01 (é a série certa de NFC-e no Gemco).
    3. Confere e faz o COMMIT.
  Depois: reenviar da FIKON o evento DEVOLUCAO 27.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @codfil int = 502, @tpnota varchar(3) = '251', @numnota numeric(12,0) = 120, @serie varchar(3) = 'U01',
        @dtnota date = '2026-11-16', @numpedven numeric(12,0) = 14206602,
        @chave_fikon varchar(44) = '23261107201916001716650010000001201073778518',
        @chave_gemco varchar(44) = '23261107201916001716550010000001201321873431';
DECLARE @erro varchar(1000) = '';

-- ===================== ANTES =====================
SELECT 'ANTES' AS momento, NUMNOTA, SERIE, STATUS, MODELONF, STATUSNFE, NUMNFE, DIGNFE, CHAVENFE
  FROM MOV_SAIDA
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND NUMNOTA = @numnota AND DTNOTA = @dtnota;

-- ===================== 1. Conferências =====================
IF NOT EXISTS (SELECT 1 FROM MOV_SAIDA
                WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota
                  AND NUMPEDVEN = @numpedven AND STATUS = 2 AND CHAVENFE = @chave_gemco
                  AND NUMNFE = 32187343 AND DIGNFE = 1)
    SET @erro = @erro + 'Nota 120 U01 nao esta como esperado (STATUS 2, chave gerada pelo Gemco, NUMNFE 32187343). ';

IF EXISTS (SELECT 1 FROM MOV_SAIDA WHERE CHAVENFE = @chave_fikon)
    SET @erro = @erro + 'Ja existe nota com a chave da FIKON. ';

IF EXISTS (SELECT 1 FROM NF_SAIDA WHERE CHAVENFE IN (@chave_fikon, @chave_gemco))
   OR EXISTS (SELECT 1 FROM HST_NF_SAIDA WHERE CHAVENFE IN (@chave_fikon, @chave_gemco))
   OR EXISTS (SELECT 1 FROM RETXML WHERE CHAVENFE IN (@chave_fikon, @chave_gemco))
    SET @erro = @erro + 'A nota tem registro de transmissao no Gemco (NF_SAIDA/HST_NF_SAIDA/RETXML): conferir com o fiscal. ';

IF EXISTS (SELECT 1 FROM ENT_NOTA WHERE TPNOTA = '26' AND CODFILSAI = @codfil AND NUMNOTASAI = @numnota AND SERIESAI = @serie)
    SET @erro = @erro + 'Ja existe devolucao gravada para a nota 120. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    RETURN;
END

-- ===================== 2 e 3. Correção =====================
BEGIN TRY
    BEGIN TRAN;

    UPDATE MOV_SAIDA
       SET CHAVENFE = @chave_fikon, MODELONF = '65', STATUSNFE = 3, NUMNFE = NULL, DIGNFE = NULL
     WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota
       AND NUMPEDVEN = @numpedven AND CHAVENFE = @chave_gemco;

    IF @@ROWCOUNT <> 1
       OR (SELECT COUNT(*) FROM MOV_SAIDA WHERE CHAVENFE = @chave_fikon) <> 1
       OR EXISTS (SELECT 1 FROM MOV_SAIDA WHERE CHAVENFE = @chave_gemco)
        RAISERROR('Conferencia final falhou; tudo foi desfeito.', 16, 1);

    COMMIT;
    PRINT 'Nota 120 U01 (filial 502) com a chave da FIKON restaurada. Reenviar a devolucao 27.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH

-- ===================== DEPOIS =====================
SELECT 'DEPOIS' AS momento, NUMNOTA, SERIE, STATUS, MODELONF, STATUSNFE, NUMNFE, DIGNFE, CHAVENFE
  FROM MOV_SAIDA
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND NUMNOTA = @numnota AND DTNOTA = @dtnota;
