/*
  08 - De-para de formas/condições de pagamento e bandeiras FIKON -> Gemco  -  10/11/2026

  Problema (nota 90, filial 15): o financeiro do cupom foi gravado com FORMA 27, que não existe em
  CAD_FORMA (a tela Consulta Mov. Saída não mostra o pagamento), e a bandeira "Maestro" não existia
  em CASH_CONVENIADAS, então caiu no convênio 1 (Mastercard CRÉDITO) com taxa 2,3.
  A ApiAcal tinha códigos fixos marcados "AJUSTAR" (crédito 26, débito 27, Pix 28) e tipo sempre 'D'.

  Este script:
    1. Cria no dbgemco duas tabelas de de-para (se ainda não existirem) e a carga inicial:
       - FIKON_DEPARA_PAGAMENTO: forma da FIKON + TEF + faixa de parcelas -> CONDPGTO + FORMA do Gemco
       - FIKON_DEPARA_BANDEIRA : bandeira da FIKON + tipo (D débito / C crédito) -> CODCON do Gemco
       A carga segue o que o PDV nativo grava (filial 1, maio/2026, ~3.000 lançamentos):
         Dinheiro               -> 01 / 1  DINHEIRO
         Débito com TEF         -> 01 / 25 DEBITO        (convênio pela bandeira, taxa CXA_CADCON)
         Débito sem TEF         -> 01 / 43 DEB MAN
         Crédito 1x  (TEF/man.) -> 88 / 4 CARTAO  ou 26 CARTAO MAN (taxa CXA_CADCON_PRAZO pelas parcelas)
         Crédito 2-6x           -> 68 / 4 ou 26
         Crédito 7-10x          -> 89 / 4 ou 26
         Pix                    -> 01 / 139 PIX MAN, convênio 43   (A CONFIRMAR: o PDV nativo usa 43; o fluxo de
                                   PEDIDO do integrador usa 49 com taxa 0,95; alternativa 135 PIX OFF / 45)
       Todas as combinações existem em CAD_FORMA da filial 15 (conferido em 10/11/2026).
    2. Reescreve por inteiro a dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO (versão do script 07 + de-para):
       - dois parâmetros novos, opcionais: @FORMA_FIKON (texto da forma como veio da FIKON) e @TEF ('S'/'N').
       - com @FORMA_FIKON: condição, forma, convênio e taxa saem das tabelas. Forma/bandeira sem de-para,
         ou combinação condição+forma que não exista em CAD_FORMA da filial, dá erro (nada é gravado e o
         erro aparece no log da ApiAcal), em vez de gravar um código que o Gemco não reconhece.
       - sem @FORMA_FIKON: comportamento do script 07 (chamadas antigas continuam funcionando).
       - parcelado no crédito: a condição do cabeçalho da nota (MOV_SAIDA.CONDPGTO) passa a ser a do
         de-para quando ela não for '01'.

  Ajustar o de-para depois: é só INSERT/UPDATE nas tabelas, sem publicar a ApiAcal.
    Ex.: trocar o Pix para PIX OFF:
      UPDATE dbgemco.dbo.FIKON_DEPARA_PAGAMENTO SET FORMA = 135, CODCON_FIXO = 45
       WHERE FORMA_FIKON IN ('PIX', 'PAGAMENTO INSTANTANEO (PIX)');
    Ex.: nova bandeira:
      INSERT INTO dbgemco.dbo.FIKON_DEPARA_BANDEIRA (BANDEIRA_FIKON, TIPO, CODCON) VALUES ('NOVA', 'C', 99);
  As comparações de texto ignoram maiúsculas e acentos ("Cartão de Débito" = "CARTAO DE DEBITO").

  Depende da ApiAcal mandar @FORMA_FIKON e @TEF (ajuste feito em PedidoFikonRepositprio.cs).

  Como rodar: no SSMS, no banco dbgemco, executar o script INTEIRO (F5). Ele guarda a versão atual
  da procedure como SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT08; se não conseguir, para (SET NOEXEC ON).
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Tabelas de de-para ===================== */
IF OBJECT_ID('dbgemco.dbo.FIKON_DEPARA_PAGAMENTO') IS NULL
BEGIN
    CREATE TABLE dbgemco.dbo.FIKON_DEPARA_PAGAMENTO (
        ID               int IDENTITY(1,1) NOT NULL CONSTRAINT PK_FIKON_DEPARA_PAGAMENTO PRIMARY KEY,
        FORMA_FIKON      varchar(60)  NOT NULL,          -- formaPagamento da FIKON (sem acento; a busca ignora acento)
        TEF              char(1)      NULL,              -- 'S', 'N' ou NULL (vale para qualquer)
        PARC_MIN         int          NOT NULL CONSTRAINT DF_FDP_PARC_MIN DEFAULT (1),
        PARC_MAX         int          NOT NULL CONSTRAINT DF_FDP_PARC_MAX DEFAULT (99),
        CONDPGTO         varchar(3)   NOT NULL,          -- CAD_CONDPG / CAD_FORMA
        FORMA            int          NOT NULL,          -- CAD_FORMA (o evento do caixa é igual à forma)
        TIPO_CONVENIADA  char(1)      NULL,              -- 'D' débito / 'C' crédito: convênio pela bandeira
        CODCON_FIXO      int          NULL,              -- convênio fixo (ex.: Pix), ignora a bandeira
        ATIVO            bit          NOT NULL CONSTRAINT DF_FDP_ATIVO DEFAULT (1),
        OBS              varchar(200) NULL,
        DT_INCLUSAO      datetime     NOT NULL CONSTRAINT DF_FDP_DT DEFAULT (GETDATE()),
        CONSTRAINT CK_FDP_TEF  CHECK (TEF IS NULL OR TEF IN ('S', 'N')),
        CONSTRAINT CK_FDP_TIPO CHECK (TIPO_CONVENIADA IS NULL OR TIPO_CONVENIADA IN ('D', 'C')),
        CONSTRAINT CK_FDP_PARC CHECK (PARC_MIN >= 1 AND PARC_MAX >= PARC_MIN)
    );
    PRINT 'Criada dbgemco.dbo.FIKON_DEPARA_PAGAMENTO.';
END;

IF OBJECT_ID('dbgemco.dbo.FIKON_DEPARA_BANDEIRA') IS NULL
BEGIN
    CREATE TABLE dbgemco.dbo.FIKON_DEPARA_BANDEIRA (
        ID              int IDENTITY(1,1) NOT NULL CONSTRAINT PK_FIKON_DEPARA_BANDEIRA PRIMARY KEY,
        BANDEIRA_FIKON  varchar(40)  NOT NULL,           -- bandeira como vem da FIKON (a busca ignora acento/maiúscula)
        TIPO            char(1)      NOT NULL,           -- 'D' débito / 'C' crédito
        CODCON          int          NOT NULL,           -- convênio do Gemco (CXA_CADCON / CXA_CADCON_PRAZO)
        ATIVO           bit          NOT NULL CONSTRAINT DF_FDB_ATIVO DEFAULT (1),
        OBS             varchar(200) NULL,
        DT_INCLUSAO     datetime     NOT NULL CONSTRAINT DF_FDB_DT DEFAULT (GETDATE()),
        CONSTRAINT CK_FDB_TIPO CHECK (TIPO IN ('D', 'C')),
        CONSTRAINT UQ_FDB UNIQUE (BANDEIRA_FIKON, TIPO)
    );
    PRINT 'Criada dbgemco.dbo.FIKON_DEPARA_BANDEIRA.';
END;
GO

/* ===================== 2. Carga inicial (só se a tabela estiver vazia) ===================== */
IF NOT EXISTS (SELECT 1 FROM dbgemco.dbo.FIKON_DEPARA_PAGAMENTO)
BEGIN
    INSERT INTO dbgemco.dbo.FIKON_DEPARA_PAGAMENTO
        (FORMA_FIKON, TEF, PARC_MIN, PARC_MAX, CONDPGTO, FORMA, TIPO_CONVENIADA, CODCON_FIXO, OBS)
    VALUES
        ('DINHEIRO',                     NULL,  1, 99, '01',   1, NULL, NULL, 'Dinheiro'),
        ('CARTAO DE DEBITO',             'S',   1, 99, '01',  25, 'D',  NULL, 'Debito com TEF -> 25 DEBITO'),
        ('CARTAO DE DEBITO',             'N',   1, 99, '01',  43, 'D',  NULL, 'Debito sem TEF -> 43 DEB MAN'),
        ('CARTAO DE DEBITO',             NULL,  1, 99, '01',  43, 'D',  NULL, 'Debito sem TEF informado -> 43 DEB MAN'),
        ('CARTAO DE CREDITO',            'S',   1,  1, '88',   4, 'C',  NULL, 'Credito 1x com TEF -> 88 ROTATIVO / 4 CARTAO'),
        ('CARTAO DE CREDITO',            'N',   1,  1, '88',  26, 'C',  NULL, 'Credito 1x sem TEF -> 88 ROTATIVO / 26 CARTAO MAN'),
        ('CARTAO DE CREDITO',            NULL,  1,  1, '88',  26, 'C',  NULL, 'Credito 1x sem TEF informado'),
        ('CARTAO DE CREDITO',            'S',   2,  6, '68',   4, 'C',  NULL, 'Credito 2-6x com TEF -> 68 / 4 CARTAO'),
        ('CARTAO DE CREDITO',            'N',   2,  6, '68',  26, 'C',  NULL, 'Credito 2-6x sem TEF -> 68 / 26 CARTAO MAN'),
        ('CARTAO DE CREDITO',            NULL,  2,  6, '68',  26, 'C',  NULL, 'Credito 2-6x sem TEF informado'),
        ('CARTAO DE CREDITO',            'S',   7, 10, '89',   4, 'C',  NULL, 'Credito 7-10x com TEF -> 89 / 4 CARTAO'),
        ('CARTAO DE CREDITO',            'N',   7, 10, '89',  26, 'C',  NULL, 'Credito 7-10x sem TEF -> 89 / 26 CARTAO MAN'),
        ('CARTAO DE CREDITO',            NULL,  7, 10, '89',  26, 'C',  NULL, 'Credito 7-10x sem TEF informado'),
        ('PAGAMENTO INSTANTANEO (PIX)',  NULL,  1, 99, '01', 139, NULL,   43, 'Pix -> 139 PIX MAN conv. 43 (A CONFIRMAR; alternativa 135 PIX OFF conv. 45)'),
        ('PIX',                          NULL,  1, 99, '01', 139, NULL,   43, 'Pix -> 139 PIX MAN conv. 43 (A CONFIRMAR; alternativa 135 PIX OFF conv. 45)');
    PRINT 'Carga inicial de FIKON_DEPARA_PAGAMENTO feita.';
END;

IF NOT EXISTS (SELECT 1 FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA)
BEGIN
    INSERT INTO dbgemco.dbo.FIKON_DEPARA_BANDEIRA (BANDEIRA_FIKON, TIPO, CODCON, OBS)
    VALUES
        ('MAESTRO',           'D', 10, 'Mastercard debito'),
        ('MASTERCARD',        'D', 10, 'Mastercard debito'),
        ('MASTERCARD DEBITO', 'D', 10, 'Mastercard debito'),
        ('MASTERCARD',        'C',  1, 'Mastercard credito'),
        ('MASTER',            'C',  1, 'Mastercard credito'),
        ('VISA ELECTRON',     'D', 11, 'Visa debito'),
        ('ELECTRON',          'D', 11, 'Visa debito'),
        ('VISA',              'D', 11, 'Visa debito'),
        ('VISA',              'C',  2, 'Visa credito'),
        ('ELO',               'D', 29, 'Elo debito'),
        ('ELO',               'C', 30, 'Elo credito'),
        ('HIPERCARD',         'C',  4, 'Hipercard'),
        ('HIPER',             'C',  4, 'Hipercard'),
        ('AMEX',              'C',  5, 'American Express'),
        ('AMERICAN EXPRESS',  'C',  5, 'American Express'),
        ('DINERS',            'C', 13, 'Diners'),
        ('CABAL',             'D', 33, 'Cabal debito'),
        ('CABAL',             'C', 42, 'Cabal credito'),
        ('SOROCRED',          'D', 36, 'Sorocred debito'),
        ('CREDZ',             'C', 31, 'Credz'),
        ('FORTBRASIL',        'C', 35, 'FortBrasil');
    PRINT 'Carga inicial de FIKON_DEPARA_BANDEIRA feita.';
END;
GO

/* ===================== 3. Cópia de segurança da procedure ===================== */
DECLARE @def nvarchar(max);

IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT08') IS NULL
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO'));
    IF @def IS NOT NULL AND @def LIKE N'%PROC%[[]dbo].[[]SP_FIKON_NOTA_GRAVAR_FINANCEIRO]%'
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO]', N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT08]');
        EXEC sys.sp_executesql @def;
    END
END

IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT08') IS NULL
BEGIN
    RAISERROR('Nao foi possivel guardar a copia de seguranca da procedure. Ela nao foi alterada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
    PRINT 'Copia guardada: SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT08.';
GO

/* ===================== 4. SP_FIKON_NOTA_GRAVAR_FINANCEIRO ===================== */
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
     @NUMCXA          = NULL,
     @NUMMOV          = NULL,
     @CODOPER         = NULL,
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
     @CODFILCXA       = 0,
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

-- Conferência
SELECT name, modify_date FROM sys.objects
 WHERE name IN ('SP_FIKON_NOTA_GRAVAR_FINANCEIRO', 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT08');
SELECT * FROM dbgemco.dbo.FIKON_DEPARA_PAGAMENTO ORDER BY FORMA_FIKON, PARC_MIN, TEF;
SELECT * FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA ORDER BY BANDEIRA_FIKON, TIPO;
GO
