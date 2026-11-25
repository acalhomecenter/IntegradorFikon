/*
  21 - Financeiro do cupom FIKON: caixa, movimento e operador na CXA_LANCTO  -  18/11/2026
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  A SP_FIKON_NOTA_GRAVAR_FINANCEIRO está igual nas duas bases (SHA-256 E8DEF213...); o script confere de novo.

  Antes: a proc chamava a SPI_LANCTOAF com NUMCXA, NUMMOV e CODOPER nulos e CODFILCXA 0, então os lançamentos
  das vendas FIKON não entravam no movimento de nenhum caixa (ex.: DM, filial 15, série U05).

  O que muda (procedure completa abaixo, passo 5):
    - De-para dbgemco.dbo.FIKON_CAD_CAIXA: filial + série da nota -> CAIXA e CODOPER.
        NUMCXA    = CAIXA do de-para
        CODOPER   = CODOPER do de-para
        CODFILCXA = filial da nota
        NUMMOV    = movimento do caixa na data da nota (CXA_MOVIMENTO): o aberto (SITUACAO 'I') primeiro,
                    depois o do mesmo operador, depois o maior NUMMOV do dia; sem movimento no dia, 1.
    - Filial/série sem de-para: continua como antes (nulos e CODFILCXA 0). A filial 502, por exemplo, não muda.
    - Não muda os lançamentos já gravados.

  Bloco 0: cria a FIKON_CAD_CAIXA se ela não existir (no DEV não existe), com a mesma estrutura da produção
  e o mesmo de-para (filial 15, série U05 -> caixa 4, operador 24). Na produção a tabela já existe e não é tocada.

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
    - O bloco 1 confere a versão da procedure e guarda a cópia SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21.
      Se algo estiver diferente, o script para (SET NOEXEC ON) e nada é alterado.
  Para voltar atrás: abrir a SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21, trocar o nome pelo original e
  executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 0. Tabela de-para do caixa (só se não existir) ===================== */
IF OBJECT_ID('dbo.FIKON_CAD_CAIXA') IS NULL
BEGIN
    CREATE TABLE dbo.FIKON_CAD_CAIXA (
        ID      int IDENTITY(1,1) NOT NULL,
        CODFIL  int NULL,
        SERIE   varchar(3) NULL,
        CAIXA   int NULL,
        CODOPER int NULL
    );
    INSERT INTO dbo.FIKON_CAD_CAIXA (CODFIL, SERIE, CAIXA, CODOPER) VALUES (15, 'U05', 4, 24);
    PRINT 'FIKON_CAD_CAIXA criada (filial 15, serie U05 -> caixa 4, operador 24).';
END
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO'));

IF @def IS NULL
   OR (HASHBYTES('SHA2_256', @def) <> 0xE8DEF2137DDED11FB1C57F82D187EB02F1E9DDE7DC9C15502391BE3FD11980B2
       AND CHARINDEX(N'script 21', @def) = 0)
BEGIN
    RAISERROR('Nada foi alterado: SP_FIKON_NOTA_GRAVAR_FINANCEIRO nao existe ou esta numa versao diferente da esperada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21') IS NULL
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO]', N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copia guardada: SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21.';
END
GO

/* ===================== 2. SP_FIKON_NOTA_GRAVAR_FINANCEIRO (completa) ===================== */
ALTER PROC [dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO]

@chavenfe varchar(44),
@condpgto VARCHAR(6),
@FORMA INT,
@NUMLAN INT,
@DTVENCTO DATE,
@numaut numeric(15,0),
@documento numeric(15,0),
@qtprc int,
@numprc int,
@VLTOTAL NUMERIC(12,4),
@bandeira varchar(30),
@tipo varchar(1),
@FORMA_FIKON varchar(60) = NULL,   -- forma de pagamento como veio da FIKON (ativa o de-para)
@TEF varchar(1) = NULL             -- 'S' / 'N' como veio da FIKON

AS

-- Reescrita em 10/11/2026 (scripts 05, 07 e 08 das procs do cupom FIKON). Ver o cabeçalho do script 08.
-- script 21 (18/11/2026): CXA_LANCTO com NUMCXA, NUMMOV, CODOPER e CODFILCXA pelo de-para
-- dbgemco.dbo.FIKON_CAD_CAIXA (filial + serie da nota -> caixa e operador). Ver o passo 5.

declare @destit varchar(3)
declare @TPCLICRC char(1)
declare @CODFIL INT
declare @totalPedido numeric(15,2)
declare @numpedven numeric(12) = 999999
declare @numnota numeric(12)
declare @CODCLI NUMERIC(9,0)
declare @TPNOTA INT
declare @FLMULTNEG VARCHAR(1)
declare @codcon int
declare @taxadm numeric(9,2)
declare @portador int
declare @CODFILCRC numeric(5,0)
declare @NUMTIT  numeric(15,0)
declare @CODORIGCRC numeric(6,0)
declare @CGCCPF   numeric(15,0)
declare @codrec numeric(9,0)
declare @desdobrorecibo varchar(6)
declare @VldescPromo numeric(15,2)
declare @serie varchar(3)
declare @dtnota date
declare @CODEVE INT

-- de-para
declare @dp_forma int
declare @dp_cond varchar(3)
declare @dp_tipo char(1)
declare @dp_codcon int
declare @tef_n char(1)
declare @parc int
declare @forma_fikon_n varchar(60)
declare @bandeira_n varchar(30)
declare @msg varchar(400)

-- caixa (script 21)
declare @numcxa numeric(3,0)
declare @nummov numeric(2,0)
declare @codoper numeric(4,0)
declare @codfilcxa numeric(5,0) = 0


-- 1. Dados da nota. Tem de vir ANTES de qualquer cálculo.
select @CODFILCRC = codfil,
       @codfil    = codfil,
       @numnota   = NUMNOTA,
       @serie     = SERIE,
       @tpnota    = tpnota,
       @dtnota    = dtnota,
       @CODCLI    = CODCLI
  from dbgemco..mov_saida
 where CHAVENFE = @chavenfe

IF @codfil IS NULL
BEGIN
    RAISERROR('SP_FIKON_NOTA_GRAVAR_FINANCEIRO: nota com a chave %s nao encontrada na MOV_SAIDA.', 16, 1, @chavenfe);
    RETURN;
END


-- 2. Total do cabeçalho pela soma dos itens. Só atualiza se a soma existir (nunca grava NULL).
set @totalPedido = (Select sum(vltotal) from mov_itsaida
                     where codfil = @codfil and numnota = @numnota and tpnota = @tpnota
                       and serie = @serie and dtnota = @dtnota)

IF @totalPedido IS NOT NULL
    UPDATE MOV_SAIDA SET VLtotal = @totalPedido where chavenfe = @chavenfe


-- 3. Condição, forma, convênio e taxa.
SET @forma_fikon_n = LTRIM(RTRIM(ISNULL(@FORMA_FIKON, '')))

IF (@forma_fikon_n <> '')
BEGIN
    -- 3a. De-para (dbgemco.dbo.FIKON_DEPARA_PAGAMENTO): forma + TEF + parcelas.
    SET @tef_n = UPPER(LEFT(LTRIM(ISNULL(@TEF, '')), 1))
    IF @tef_n NOT IN ('S', 'N') SET @tef_n = NULL

    SET @parc = CASE WHEN ISNULL(@qtprc, 0) < 1 THEN 1 ELSE @qtprc END

    SELECT TOP (1) @dp_cond   = d.CONDPGTO,
                   @dp_forma  = d.FORMA,
                   @dp_tipo   = d.TIPO_CONVENIADA,
                   @dp_codcon = d.CODCON_FIXO
      FROM dbgemco.dbo.FIKON_DEPARA_PAGAMENTO d
     WHERE d.ATIVO = 1
       AND d.FORMA_FIKON COLLATE Latin1_General_CI_AI = @forma_fikon_n COLLATE Latin1_General_CI_AI
       AND @parc BETWEEN d.PARC_MIN AND d.PARC_MAX
       AND (d.TEF = @tef_n OR d.TEF IS NULL)
     ORDER BY CASE WHEN d.TEF = @tef_n THEN 0 ELSE 1 END, d.ID

    IF @dp_forma IS NULL
    BEGIN
        SET @msg = 'Forma de pagamento FIKON "' + @forma_fikon_n + '" (TEF ' + ISNULL(@tef_n, '-') + ', '
                 + CAST(@parc AS varchar(5)) + ' parcela(s)) sem de-para em dbgemco.dbo.FIKON_DEPARA_PAGAMENTO.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbgemco..CAD_FORMA WHERE CODFIL = @codfil AND CONDPGTO = @dp_cond AND FORMA = @dp_forma)
    BEGIN
        SET @msg = 'De-para da forma FIKON "' + @forma_fikon_n + '" aponta para condicao ' + @dp_cond + ' / forma '
                 + CAST(@dp_forma AS varchar(5)) + ', que nao existe em CAD_FORMA da filial ' + CAST(@codfil AS varchar(5)) + '.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    SET @condpgto = @dp_cond
    SET @FORMA    = @dp_forma

    -- 3b. Convênio: fixo do de-para, ou pela bandeira (dbgemco.dbo.FIKON_DEPARA_BANDEIRA).
    IF @dp_codcon IS NOT NULL
        SET @codcon = @dp_codcon
    ELSE IF @dp_tipo IS NOT NULL
    BEGIN
        SET @bandeira_n = LTRIM(RTRIM(ISNULL(@bandeira, '')))

        SELECT TOP (1) @codcon = b.CODCON
          FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA b
         WHERE b.ATIVO = 1
           AND b.TIPO = @dp_tipo
           AND b.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI = @bandeira_n COLLATE Latin1_General_CI_AI

        IF @codcon IS NULL
        BEGIN
            SET @msg = 'Bandeira FIKON "' + @bandeira_n + '" (' + CASE @dp_tipo WHEN 'D' THEN 'debito' ELSE 'credito' END
                     + ') sem de-para em dbgemco.dbo.FIKON_DEPARA_BANDEIRA.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END
    END

    -- 3c. Taxa de administração do convênio: crédito pela quantidade de parcelas, os demais pela taxa única.
    IF @codcon IS NOT NULL
    BEGIN
        IF @dp_tipo = 'C'
            SET @taxadm = (SELECT MAX(g.TAXADM) FROM dbgemco..CXA_CADCON_PRAZO (nolock) g WHERE g.CODCON = @codcon AND g.PRACON = @parc)
        ELSE
            SET @taxadm = (SELECT MAX(g.TAXADM) FROM dbgemco..CXA_CADCON (nolock) g WHERE g.CODCON = @codcon)
    END

    -- 3d. Crédito parcelado: a condição da nota passa a ser a do de-para.
    IF @condpgto <> '01'
        UPDATE dbgemco..mov_saida WITH (READCOMMITTED) SET CONDPGTO = @condpgto WHERE CHAVENFE = @chavenfe
END
ELSE
BEGIN
    -- Sem @FORMA_FIKON: regra do script 07 (forma numérica decidida pela ApiAcal).
    IF (@FORMA = 1)
    BEGIN
        SET @taxadm = NULL
        SET @codcon = NULL
    END
    ELSE
    BEGIN
        IF(@tipo='D')
        BEGIN
            SET @taxadm = (SELECT isnull(max(g.TAXADM),2.3) FROM dbgemco..CXA_CADCON(nolock) g INNER JOIN dbaplicativos..CASH_CONVENIADAS (nolock) c on g.codcon = TRY_CAST(c.codcon AS int) WHERE CAST(c.bandeira AS varchar(20)) = @bandeira and c.tipo=@tipo )
        END
        ELSE
        BEGIN
            SET @taxadm = (SELECT isnull(max(g.TAXADM),2.3) FROM dbgemco..CXA_CADCON_PRAZO(nolock) g INNER JOIN dbaplicativos..CASH_CONVENIADAS (nolock) c on g.codcon = TRY_CAST(c.codcon AS int) WHERE CAST(c.bandeira AS varchar(20)) = @bandeira AND g.PRACON=@qtprc and c.tipo=@tipo )
        END

        SET @codcon = (SELECT isnull(max(TRY_CAST(codcon AS int)),1) FROM dbaplicativos..CASH_CONVENIADAS(nolock) WHERE CAST(BANDEIRA AS varchar(20)) = @bandeira and tipo = @tipo )
    END
END


-- 4. Evento do caixa = forma de pagamento (padrão da filial: Dinheiro 1 -> 1, Débito 25 -> 25, ...).
SET @CODEVE = @FORMA


if(@numaut = 0)
begin
set @numaut = null
end

if(@documento = 0)
begin
set @documento = null
end

if(@taxadm = 0)
begin
set @taxadm = null
end

if(@codcon = 0)
begin
set @codcon = null
end

if(@FLMULTNEG = '')
begin
set @FLMULTNEG = 'N'
end

if(@CODFILCRC = 0)
begin
set @CODFILCRC = null
end

if(@NUMTIT = 0)
begin
set @NUMTIT = null
end

if(@codeve = 29)
begin
set @TPCLICRC = '1'
end
 else
  begin
 set @TPCLICRC = null
 end

if(@CODORIGCRC = 0)
begin
set @CODORIGCRC = null
end

if(@CGCCPF = 0)
begin
set @CGCCPF = null
end

if(@codrec = 0)
begin
set @codrec = null
end

if(@numprc>9)
begin
set @destit = CONVERT(varchar,@numprc)
end
 else
  begin
 set @destit = '0'+ CONVERT(varchar,@numprc)
 end

 set @FLMULTNEG = (select ISNULL(flmultneg,'N') from dbgemco..CAD_CONDPG where codfil=@CODFIL and CONDPGTO=@condpgto)


 update dbgemco..mov_saida WITH (READCOMMITTED) set QTPRC=@qtprc where CHAVENFE=@chavenfe


 if(@desdobrorecibo<>'')
begin
 set @destit = @desdobrorecibo
end

if(@condpgto = '01' )
begin

--  if(@taxadm > 0 or @forma=135)
--  begin
--  set @NUMLAN = @numprc
--  end

set @numprc = 1

end


-- Regras fixas antigas (Pix 139 -> convênio 49 / depósito 5): só sem o de-para.
-- Com @FORMA_FIKON, convênio e taxa vêm das tabelas de de-para.
if(@forma_fikon_n = '' AND @CODEVE = 139)
 begin

  set @numaut =1
  set @codcon = 49
  set @taxadm = 0

 end

 if(@forma_fikon_n = '' AND @CODEVE = 5)
 begin


  set @codcon = null
  set @taxadm = 0

 end

-- 5. Caixa (script 21): de-para filial + serie da nota -> caixa e operador (dbgemco.dbo.FIKON_CAD_CAIXA).
--    NUMMOV = movimento do caixa na data da nota (CXA_MOVIMENTO): o aberto primeiro, depois o do mesmo
--    operador, depois o maior do dia; sem movimento no dia, 1.
--    Sem de-para para a filial/serie, fica como antes: NUMCXA/NUMMOV/CODOPER nulos e CODFILCXA 0.
SELECT TOP (1) @numcxa = c.CAIXA, @codoper = c.CODOPER
  FROM dbgemco.dbo.FIKON_CAD_CAIXA c
 WHERE c.CODFIL = @codfil AND c.SERIE = @serie AND c.CAIXA IS NOT NULL
 ORDER BY c.ID

IF @numcxa IS NOT NULL
BEGIN
    SET @codfilcxa = @codfil

    SELECT TOP (1) @nummov = m.NUMMOV
      FROM dbgemco..CXA_MOVIMENTO m (nolock)
     WHERE m.CODFIL = @codfil AND m.NUMCXA = @numcxa AND m.DATAINI = @dtnota
     ORDER BY CASE WHEN m.SITUACAO = 'I' THEN 0 ELSE 1 END,
              CASE WHEN m.CODOPER = @codoper THEN 0 ELSE 1 END,
              m.NUMMOV DESC

    IF @nummov IS NULL
        SET @nummov = 1
END

declare @dtproc date = cast(getdate() as date)


-- Mesmos valores das versões anteriores, por nome de parâmetro (TIPOPED 1 = venda de PDV, script 07).
exec dbgemco.dbo.SPI_LANCTOAF
     @VERSAO          = 1,
     @CODFIL          = @codfil,
     @FILPED          = @codfil,
     @TIPOPED         = 1,
     @NUMPED          = @numpedven,
     @CONDPGTO        = @condpgto,
     @FORMA           = @forma,
     @NUMBCO          = NULL,
     @NUMAGE          = NULL,
     @NUMCTA          = NULL,
     @NUMORP          = NULL,
     @NUMGRP          = NULL,
     @NUMCOT          = NULL,
     @NUMAUT          = @numaut,
     @VALLAN          = @vltotal,
     @STATUS          = 0,
     @CODEVE          = @codeve,
     @NUMLAN          = @numlan,
     @CODCLI          = @codcli,
     @NUMPRC          = @numprc,
     @NUMPRCCOB       = @numprc,
     @NUMCONTRAFIN    = NULL,
     @DIGCONTRAFIN    = NULL,
     @DATREF          = @dtproc,
     @DTVCTO          = @dtvencto,
     @INTEGRACRC      = 'N',
     @TPNOTA          = @tpnota,
     @NUMNOT          = @numnota,
     @SERIE           = @serie,
     @CTACONTAB       = NULL,
     @CODPLA          = NULL,
     @NUMDEPOSIDENT   = NULL,
     @DATDEP          = @dtproc,
     @NUMCHQ          = NULL,
     @NUMDOC          = @documento,
     @DEPCHQ          = NULL,
     @CODCON          = @codcon,
     @NUMCARTAO       = @NUMLAN,
     @VALIDCARTAO     = NULL,
     @FLGERAER        = 'N',
     @CODCHQ          = NULL,
     @TAXADM          = @taxadm,
     @DATENT          = @dtnota,
     @DESTIT          = @destit,
     @CODPORT         = @portador,
     @CODFILCRC       = @CODFILCRC,
     @NUMTIT          = @NUMTIT,
     @TPCLICRC        = @TPCLICRC,
     @CODORIGCRC      = @CODORIGCRC,
     @CGCCPF          = @CGCCPF,
     @NUMCXA          = @numcxa,      -- script 21
     @NUMMOV          = @nummov,      -- script 21
     @CODOPER         = @codoper,     -- script 21
     @CODCONVENIO     = NULL,
     @CODFUNC         = NULL,
     @CODCONFIN       = NULL,
     @DTTURNO         = '12/30/1899',
     @VLTROCO         = NULL,
     @CODREC          = @codrec,
     @DIGAGE          = NULL,
     @DIGCTA          = NULL,
     @DIGCHQ          = NULL,
     @SERIECONTRAFIN  = NULL,
     @TPCONTRATO      = NULL,
     @TID             = NULL,
     @NUMAUTORIZACAO  = @numaut,
     @FLCTRLINTERNO   = NULL,
     @CODFILCXA       = @codfilcxa,   -- script 21 (0 sem de-para, como antes)
     @NOSSONUMERO     = NULL,
     @CODSEGCARTAO    = '0',
     @CODBARRA        = NULL,
     @FILORI          = @codfil,
     @CODTPSEGUR      = NULL,
     @VLBOLETO        = NULL,
     @NRAGRUPCARNE    = NULL,
     @DESDAGRUP       = NULL,
     @VLTAC           = 0,
     @VLTARBANCARIA   = 0,
     @FLMULTNEG       = @flmultneg,
     @PJUROS          = 0,
     @QTPRC           = 0,
     @CARENCIA        = 0,
     @NUMTAB          = ''
GO

SET NOEXEC OFF;
GO

-- Conferência: a procedure deve ter o ajuste, a cópia deve existir e o de-para do caixa.
SELECT o.name, o.modify_date,
       CASE WHEN o.name = 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO'
            THEN CASE WHEN CHARINDEX('script 21', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script21
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_NOTA_GRAVAR_FINANCEIRO', 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT21')
 ORDER BY o.name;

SELECT c.ID, c.CODFIL, c.SERIE, c.CAIXA, c.CODOPER,
       (SELECT TOP (1) CONCAT('NUMMOV ', m.NUMMOV, ' / operador ', m.CODOPER, ' / ', m.SITUACAO)
          FROM CXA_MOVIMENTO m
         WHERE m.CODFIL = c.CODFIL AND m.NUMCXA = c.CAIXA AND m.DATAINI = CAST(GETDATE() AS date)
         ORDER BY CASE WHEN m.SITUACAO = 'I' THEN 0 ELSE 1 END, m.NUMMOV DESC) AS movimento_hoje
  FROM FIKON_CAD_CAIXA c
 ORDER BY c.CODFIL, c.SERIE;
GO
