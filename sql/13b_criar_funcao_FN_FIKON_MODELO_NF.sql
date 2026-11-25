/*
  13b - Cria a função dbo.FN_FIKON_MODELO_NF  -  16/11/2026  (URGENTE)
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  Por quê: as procedures SP_FIKON_INTEGRA_MOV_SAIDA, SP_FIKON_INTEGRA_MOV_ITSAIDA e
  SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA já foram alteradas pelo script 13 e chamam esta função, mas ela não foi
  criada (só os blocos de ALTER do script foram executados). Sem a função, todo faturamento e todo cupom
  da FIKON falham com "Cannot find either column dbo or the user-defined function dbo.FN_FIKON_MODELO_NF".

  Regra:
    1. Chave de acesso com 44 dígitos: modelo da chave (posições 21-22, "55" ou "65").
    2. Sem chave válida: série começando com "U" (padrão do cupom no Gemco) -> "65"; senão -> "55".

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.FN_FIKON_MODELO_NF') IS NULL
    EXEC sys.sp_executesql N'
CREATE FUNCTION dbo.FN_FIKON_MODELO_NF (@chave varchar(60), @serie varchar(3))
RETURNS varchar(2)
AS
-- Script 13 (16/11/2026): modelo da nota da FIKON.
--   Chave de acesso com 44 dígitos: modelo da chave (posições 21-22, "55" ou "65").
--   Sem chave válida: série começando com "U" (padrão do cupom no Gemco) -> "65"; senão -> "55".
BEGIN
    DECLARE @c varchar(60) = LTRIM(RTRIM(ISNULL(@chave, '''')));

    IF LEN(@c) = 44 AND @c NOT LIKE ''%[^0-9]%'' AND SUBSTRING(@c, 21, 2) IN (''55'', ''65'')
        RETURN SUBSTRING(@c, 21, 2);

    IF LTRIM(ISNULL(@serie, '''')) LIKE ''U%''
        RETURN ''65'';

    RETURN ''55'';
END';
ELSE
    PRINT 'A funcao dbo.FN_FIKON_MODELO_NF ja existe.';
GO

-- Conferência: a função deve existir e o teste deve dar 65, 55, 55, 65, 65.
SELECT name, type_desc, create_date FROM sys.objects WHERE name = 'FN_FIKON_MODELO_NF';
GO

IF OBJECT_ID('dbo.FN_FIKON_MODELO_NF') IS NOT NULL
    EXEC sys.sp_executesql N'
SELECT t.descricao, t.serie, dbo.FN_FIKON_MODELO_NF(t.chave, t.serie) AS modelo, t.esperado
  FROM (VALUES (''NFC-e serie U01 (chave mod 65)'', ''U01'', ''23261107201916001716650010000001201073778518'', ''65''),
               (''NF-e serie 1 (chave mod 55)'',     ''1'',   ''23261107201916001392550010000000231092417994'', ''55''),
               (''NF-e serie 2 sem chave'',          ''2'',   '''', ''55''),
               (''Cupom U04 sem chave'',             ''U04'', NULL, ''65''),
               (''Cupom serie 444 (chave mod 65)'',  ''444'', ''23261107201916001392654440000000971009960341'', ''65'')) t(descricao, serie, chave, esperado);';
GO
