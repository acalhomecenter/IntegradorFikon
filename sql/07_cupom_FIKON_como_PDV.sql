/*
  07 - Cupom FIKON gravado como venda de PDV (TIPOPED = 1)  -  10/11/2026

  Substitui o script 05 (mesmas duas procedures, reescritas por inteiro, com tudo o que o 05 já
  corrigia) e acrescenta o ajuste abaixo.

  Problema (nota 86, filial 15): na Consulta Mov. Saída, "Formas de Pagamento" mostrava pagamentos
  de outros cupons. A tela do Gemco escolhe como achar o financeiro pelo MOV_SAIDA.TIPOPED:
    - TIPOPED = 0 (pedido):  CXA_LANCTO.CODFIL = MOV_SAIDA.FILPED AND CXA_LANCTO.NUMPED = MOV_SAIDA.NUMPEDVEN
                             AND CXA_LANCTO.TIPOPED = MOV_SAIDA.TIPOPED
      -> como todo cupom da integração usa o pedido fictício 999999, a tela trazia o financeiro
         de TODOS os cupons da filial (o DISTINCT juntava as linhas iguais).
    - TIPOPED = 1 (PDV):     CXA_LANCTO.CODFIL = MOV_SAIDA.CODFIL AND CXA_LANCTO.NUMNOT = MOV_SAIDA.NUMNOTA
                             AND CXA_LANCTO.TPNOTA = MOV_SAIDA.TPNOTA AND CXA_LANCTO.SERIE = MOV_SAIDA.SERIE
                             AND CXA_LANCTO.DATENT = MOV_SAIDA.DTNOTA
      -> é como o PDV nativo grava (conferido na nota 90430 série U04 da filial 1: NUMPEDVEN 999999,
         TIPOPED 1, CXA_LANCTO com a série e a data da nota). Consultas capturadas no cache do SQL
         do DB-TREINO em 10/11/2026.

  O que muda em relação ao script 05:
    SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA : MOV_SAIDA.TIPOPED = 1 (era 0).
    SP_FIKON_NOTA_GRAVAR_FINANCEIRO  : na SPI_LANCTOAF, @TIPOPED = 1 (era 0), @SERIE = série da nota
                                       (era '0' fixo) e @DATENT = data da nota (era a data do dia).

  O que o script 05 já corrigia continua aqui:
    - financeiro: total do cabeçalho não é mais apagado; CODEVE = FORMA; CODCLI da nota; dinheiro sem
      taxa/convênio; erro se a nota não existir; chamada da SPI_LANCTOAF por nome de parâmetro.
    - cabeçalho: cliente "C"+código do Gemco, "0" consumidor final, código desconhecido vira
      consumidor final com o código da FIKON na OBS; trava contra nota duplicada pela chave.

  Cupons já gravados (TIPOPED 0 / SERIE '0' no caixa) não mudam com este script.

  Como rodar: no SSMS, no banco dbgemco, executar o script INTEIRO (F5). O 1º bloco guarda cópias
  (<nome>_BKP_SCRIPT07); se não conseguir, o script para (SET NOEXEC ON) e nada é alterado.
  Para voltar atrás: abrir a <nome>_BKP_SCRIPT07, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Cópias de segurança ===================== */
DECLARE @def nvarchar(max), @ok bit = 1;

IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT07') IS NULL
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO'));
    IF @def IS NULL OR @def NOT LIKE N'%PROC%[[]dbo].[[]SP_FIKON_NOTA_GRAVAR_FINANCEIRO]%'
        SET @ok = 0;
    ELSE
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO]', N'[dbo].[SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT07]');
        EXEC sys.sp_executesql @def;
    END
END

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT07') IS NULL
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA'));
    IF @def IS NULL OR @def NOT LIKE N'%PROC%[[]dbo].[[]SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA]%'
        SET @ok = 0;
    ELSE
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA]', N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT07]');
        EXEC sys.sp_executesql @def;
    END
END

IF @ok = 0 OR OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT07') IS NULL
          OR OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT07') IS NULL
BEGIN
    RAISERROR('Nao foi possivel guardar as copias de seguranca. Nada foi alterado.', 16, 1);
    SET NOEXEC ON;   -- os blocos seguintes não são executados
END
ELSE
    PRINT 'Copias guardadas: SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT07 e SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT07.';
GO

/* ===================== 2. SP_FIKON_NOTA_GRAVAR_FINANCEIRO ===================== */
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
@tipo varchar(1)

AS

-- Reescrita em 10/11/2026 (scripts 05 e 07 de reescrita das procs do cupom FIKON). Ver o cabeçalho do script.

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


-- 1. Dados da nota. Tem de vir ANTES de qualquer cálculo (antes era lido depois da soma do total).
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


-- 3. Evento do caixa = forma de pagamento (padrão da filial: Dinheiro 1 -> evento 1, forma 43 -> evento 43).
SET @CODEVE = @FORMA


-- 4. Taxa de administração e convênio: só para cartão. Dinheiro vai sem taxa e sem convênio,
--    como o lançamento normal do pedido (antes caía no padrão 2,3 / convênio 1).
IF (@FORMA = 1)
BEGIN
    SET @taxadm = NULL
    SET @codcon = NULL
END
ELSE
BEGIN
    IF(@tipo='D')
    BEGIN
        -- Correção no ON: Usa TRY_CAST para evitar erro caso c.codcon seja varchar com lixo/vazio
        SET @taxadm = (SELECT isnull(max(g.TAXADM),2.3) FROM dbgemco..CXA_CADCON(nolock) g INNER JOIN dbaplicativos..CASH_CONVENIADAS (nolock) c on g.codcon = TRY_CAST(c.codcon AS int) WHERE CAST(c.bandeira AS varchar(20)) = @bandeira and c.tipo=@tipo )
    END
    ELSE
    BEGIN
        -- Correção no ON: Mesmo tratamento para vendas a prazo/crédito
        SET @taxadm = (SELECT isnull(max(g.TAXADM),2.3) FROM dbgemco..CXA_CADCON_PRAZO(nolock) g INNER JOIN dbaplicativos..CASH_CONVENIADAS (nolock) c on g.codcon = TRY_CAST(c.codcon AS int) WHERE CAST(c.bandeira AS varchar(20)) = @bandeira AND g.PRACON=@qtprc and c.tipo=@tipo )
    END

    -- Busca o código do convênio convertendo com segurança se necessário
    SET @codcon = (SELECT isnull(max(TRY_CAST(codcon AS int)),1) FROM dbaplicativos..CASH_CONVENIADAS(nolock) WHERE CAST(BANDEIRA AS varchar(20)) = @bandeira and tipo = @tipo )
END


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


if(@CODEVE = 139)
 begin

  set @numaut =1
  set @codcon = 49
  set @taxadm = 0

 end

 if(@CODEVE = 5)
 begin


  set @codcon = null
  set @taxadm = 0

 end

declare @dtproc date = cast(getdate() as date)


-- Mesmos valores da chamada posicional anterior, agora por nome de parâmetro.
exec dbgemco.dbo.SPI_LANCTOAF
     @VERSAO          = 1,
     @CODFIL          = @codfil,
     @FILPED          = @codfil,
     @TIPOPED         = 1,                -- venda de PDV (antes 0 = pedido)
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
     @CODEVE          = @codeve,          -- antes: NULL (nunca preenchido)
     @NUMLAN          = @numlan,
     @CODCLI          = @codcli,          -- antes: NULL (nunca preenchido)
     @NUMPRC          = @numprc,
     @NUMPRCCOB       = @numprc,
     @NUMCONTRAFIN    = NULL,
     @DIGCONTRAFIN    = NULL,
     @DATREF          = @dtproc,
     @DTVCTO          = @dtvencto,
     @INTEGRACRC      = 'N',
     @TPNOTA          = @tpnota,
     @NUMNOT          = @numnota,
     @SERIE           = @serie,           -- série da nota (antes '0' fixo)
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
     @DATENT          = @dtnota,          -- data da nota (a tela liga DATENT = DTNOTA)
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

/* ===================== 3. SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA ===================== */
ALTER proc [dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA]
@numnota numeric(12,0),
@serie varchar(3),
@chave varchar(44),
@hrhora datetime ,
@vltotal numeric(15,2),
@codcli varchar(15),
@estabelecimento numeric(15,0),
@cpfconsultor varchar(14)

 as

-- Reescrita em 10/11/2026 (scripts 05 e 07 de reescrita das procs do cupom FIKON). Ver o cabeçalho do script.

-- TRAVA_CHAVE_DUPLICADA: não grava nota cuja chave já existe na MOV_SAIDA (ativa ou cancelada).
IF LEN(LTRIM(RTRIM(ISNULL(@chave, '')))) = 44
   AND EXISTS (SELECT 1 FROM MOV_SAIDA WHERE CHAVENFE = LTRIM(RTRIM(@chave)))
BEGIN
    DECLARE @msg_trava varchar(300) = 'Nota com chave ' + LTRIM(RTRIM(@chave))
        + ' ja existe na MOV_SAIDA (ativa ou cancelada): gravacao recusada para evitar duplicidade.';
    RAISERROR(@msg_trava, 16, 1);
    RETURN;
END

BEGIN TRY

   begin tran


declare @numpedven numeric(12,0)
declare @codfil int
declare @dtnota date = getdate()
declare @dtemissao date = getdate()
declare @dtpedido date
declare @dtentrega date = getdate()
declare @condpgto  varchar(3)
declare @estado varchar(2)
declare @codvendr int
declare @endcob int = 0
declare @endent int = 0
declare @peso numeric(12,3)
declare @praca numeric(5,0)
declare @obs varchar(255)
declare @vlbaseicm numeric(15,2)
declare @vldesconto numeric(15,2)
declare @vlfrete numeric(15,2)
declare @vlicm numeric(15,2)
declare @vlicmret numeric(15,2)
declare @vlmercad numeric(15,2)
declare @vlentrada numeric(15,2)
declare @vloutras numeric(15,2)
declare @vlbaseicmssub numeric(15,2)
declare @endfat int = 0
declare @cliente varchar(100)
declare @vlvdvista numeric(15,2)
declare @vlvdliq numeric(15,2)
declare @coduser numeric(6,0) = '537'
declare @qtprc int
declare @vlprc numeric(15,2)
declare @identproc varchar(250)
declare @codnatop numeric(3,0)=540
declare @codnatopdifcompl numeric(2)=5
declare @vlbaseicmd numeric(15,2)
declare @vlicmd numeric(15,2)
declare @modelonf varchar(4)='65'
declare @DATAHORAUTC varchar(50) = FORMAT(SYSDATETIMEOFFSET(), 'yyyy-MM-ddTHH:mm:sszzz');
declare @vlbasecbs numeric(15,2)
declare @vlcbs numeric(15,2)
declare @vlbaseibs numeric(15,2)
declare @vlibs numeric(15,2)
declare @vlbaseibsmun numeric(15,2)
declare @vlibsmun numeric (15,2)
declare @tpnota varchar(4)
declare @statusnfe int = 0
declare @numcxa varchar(3)
declare @codcli_gemco numeric(12,0) = NULL
declare @codcli_fikon varchar(15) = LTRIM(RTRIM(ISNULL(@codcli, '')))

if(@serie='1')
begin
set @statusnfe=2
set @modelonf = '55'
end
  else
  begin
    set @statusnfe=3
	set @modelonf = '65'
  end

 set @numpedven = 999999
 set @codfil = (select filial_genco from [FIKON_VINCULO_FILIAL] where  filial_fikon = @estabelecimento)
 set @codvendr = (select codvendr from dbgemco..VEN_VEND where CODFIL=@codfil and CGCCPF = @cpfconsultor  )
 set @condpgto = '01'

 -- Cliente. A FIKON pode mandar:
 --   "C" + código do Gemco (ex.: C197794) -> esse cliente;
 --   "0"                                  -> consumidor final;
 --   o código interno dela (ex.: 159263014), que NÃO é código do Gemco.
 -- Código não reconhecido ou cliente inexistente: consumidor final, com o código da FIKON na OBS
 -- (antes o código era gravado do jeito que veio e o NOME ficava nulo).
 if (@codcli_fikon LIKE 'C%' AND LEN(@codcli_fikon) BETWEEN 2 AND 13
     AND SUBSTRING(@codcli_fikon, 2, 15) NOT LIKE '%[^0-9]%')
     set @codcli_gemco = CAST(SUBSTRING(@codcli_fikon, 2, 15) AS numeric(12,0))
 else if (@codcli_fikon = '0')
     set @codcli_gemco = 0

 if (@codcli_gemco IS NOT NULL)
     select @cliente = c.NOMCLI, @praca = e.praca
       from dbgemco..CAD_CLIENTE as c
       left join dbgemco..CAD_ENDCLI e on e.CODCLI = c.CODCLI and e.codend = 0
      where c.codcli = @codcli_gemco

 if (@cliente IS NULL)
 begin
     if (@codcli_fikon NOT IN ('', '0'))
         set @obs = 'CLIENTE FIKON ' + @codcli_fikon + ' SEM CADASTRO CORRESPONDENTE NO GEMCO'

     set @codcli_gemco = 0

     select @cliente = c.NOMCLI, @praca = e.praca
       from dbgemco..CAD_CLIENTE as c
       left join dbgemco..CAD_ENDCLI e on e.CODCLI = c.CODCLI and e.codend = 0
      where c.codcli = 0
 end

 set @vldesconto = 0
 set @vlentrada = 0
 set @vlfrete = 0
 set @vlmercad = 0
 set @tpnota = 251
 set @vlbaseicm = 0
 set @vlvdvista = 0
 set @vlvdliq = 0
 set @qtprc = 1
 set @endfat = 0
 set @vlprc = 0
 set @vlicm = 0
 set @vlbaseicmssub = 0
 set @vlicmret = 0
 set @vloutras = 0
 set @estado = 'CE'
 set @numcxa = 1

     INSERT  INTO MOV_SAIDA (CODFIL, TPNOTA, NUMNOTA,  SERIE,     DTNOTA, TIPOPED, NUMCTRL,   DTEMISSAO,    DTPEDIDO,   DTCANCEL,  DTENTREGA,    CONDPGTO,    ESTADO,   GUIA, ALIQICM, CODNATOP,     NUMPEDVEN,    CODCLI,    CODVENDR, NUMCXA, CODTRANSP, CODMENSAG, ZONAENT, SEQENT, ENDCOB,      ENDENT,     FLENTRET, LOCAL, ORIGEM, LOTE, PESO,   PRACA,  SETOR, SITUACAO, TPOCORR, TPPEND, TPTRANS, AUTORIZAC, NFPRESENT, OBS, VLDESPACES, VLACRESCIM,    VLBASEICMS,         VLDESCONTO,          VLDESPFIN, VLDESPSICM,    VLFRETE,    VLICM,     VLICMRET,  VLIPI, VLMERCAD,    VLOUTDESP, VLSEGURO, VLENTRADA, CUBAGVEIC, CUBAGNF, STATUS, CODCLIPRES, FILPED,     NUMCONTRA, DEPTVD, VLISENTO, VLOUTRAS, DATCOT, LOTCOT, NUMLAN, VLBASEIPI, VLTOTAL, VLREDICMS, FLRICMS, REBATE, QTINDICE, PESOLIQ, VLBASEICMSSUB, VLISS, CODAWBDET, CODAWB, CODCOURIER, AEROORIG, AERODEST, DTDARF, DTEXP, FLSPC, VLII, CODSEGURADORA, NUMPEDCLI, CODMODAL, VLVDLIQ, CODNATOPCLI, FLINTEGRACAO, DIGCONTRAFIN, CODDEVOL,    HRHORA,           HRDURACAO, CIFFOB, CODFILSOLIC, TPFRETE,  ENDFAT, FLNFMANUAL, CODOCORENT, CODTRANSPRED, NUMCONTRAFIN, VLJUROSFIN, PJUROS,        DTATUEST,     FLATUEST, FLDUPLICATA, VLTOTALIND, SEXO, IDADE, CODFUNC, HRHORAINI, DTLIBPED, FLTPVENDA, CODFILSIMPFAT, TPNOTASIMPFAT, NUMNOTASIMPFAT, SERIESIMPFAT, CODFILPDV, DTNOTAPDV, FLNOTAPDV, NUMNOTAPDV, NUMPDV, SERIEPDV, TPNOTAPDV, CONTROLE,     NOME,                     CODCLIENT, ENDCLIENT, CODUSER,       VLAGREGACRC, VLISENTOIPI, VLOUTRASIPI, QTPRC,  VLPRC,  QTVOLUME, FLFISCAL, OBSFISCAL, DTVALID, FLREPLICA,  IDENTPROC,  CODNATOPDIF, CODNATOPCOMPL, NUMNOTADEBITO, NUMNOTAENT, SERIEENT, FLINSTALATERCEIRO, VLFRETETERCEIRO, FLINTFIN, DTALTERACAO, USERIDALT , VLIRRF, TPCONTRATO, SERIECONTRAFIN, NOMERECEB, DTRECEB, HRRECEB, DTSIMPFAT, VLJUROS, CODCLIPUBLICIDADE, CODENDCLIPUBLICIDADE, NUMCTRLPART, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, NRSERIEECF, VLBASEICMD, VLICMD,  VLPISCOFINSCSLL, FLDEVOL, CODTRANSP2, FLSEGURO, VLDESCNOTA, VLBASEICMORIGREPI, VLICMORIGREPI, VLICMREPI, FLTRANSFANEXOAUT, TPPGTO, INTEGRACRC, CODFILORIG, NUMNOTAORIG, SERIEORIG, TPNOTAORIG, DTNOTAORIG, VLTOTALSIMPFAT, VLICMDESCONTO, TOTCUPOMPROMOCIONAL, VLICMTRANSF, ANOMESAPU, VLTAC, CARENCIA, VLTARBANCARIA, NUMOSMONTAG, STATUSOSMONTAG, VLPISDESCONTO, VLCOFDESCONTO, MODELONF, VLBASEICMSDIFSAI, VLICMDIFSAI, NUMORC, DTPREVRETMET, DTUSEREEMISAO, CODUSEREEMISAO, DTAUTORIZACAONFE, NUMNFE, DIGNFE, STATUSNFE, DTCANCELAMENTONFE, NSU, DTIMPRESSAO, DATENT, ESTADOPLACA, ESTADOPLACACARRETA, PLACACARRETA, PLACAVEIC  ,CODNATOPDIFCOMPL, VLTOTPISRET, VLTOTCSLLRET, VLTOTIRRET, VLTOTCOFINSRET, VLNTRIBUTD, VLICMRETV , VLICMCREDITO, VLIBPT, ALIQIBPT,     DATAHORAUTC,    FLMOTORDEPROMOCOES, CODOPER, CHAVEIBPT, FONTEIBPT, ALIQIBPTEST, VLIBPTEST, ALIQIBPTMUN, VLIBPTMUN,                 CHAVENFE,                               CODMODELOSEFAZENTNFE, CODFILDESTENTNFE, CODREMETENTNFE, SERIEENTNFE, DTNOTAENTNFE, NUMNOTAENTNFE, CHAVENFEENTNFE, SEQINVDATA, VLFECEP, VLFECEPST, VLICMPARTUF, VLICMPART, CODCONTR,   CHAVENFEREF,NRSERIEECFREF, FLUTILSAIDA, VLICMSDESON, CODFORNEINTERMEDIADOR, FLPAGINTERMEDIADOR, CODPROFISSAOCASHBACK, VLBASECBS,   VLCBS,      VLBASEIBS,     VLIBS,         VLBASEIBSMUN,                   VLIBSMUN,     VLBASEIS,      VLIS, PERCREDUTOR , tpajuste, FLEXCFCPBCPISCOFINS, FLEXCICMSBCPISCOFINS)
     VALUES (         @codfil, @tpnota, @numnota, @serie,  @dtnota,  1,  NULL,   @dtemissao,  @dtpedido,  NULL,  @dtentrega,  @condpgto,  @estado, NULL, NULL,   NULL,    @numpedven, @codcli_gemco,  @codvendr,  @numcxa,   0,    0,    NULL,  NULL,  @endcob,  @endent,   NULL,   1,    0, null, @peso, @praca,  0,   NULL,   NULL,  NULL,  NULL,  '0',    NULL, @obs,   0,     NULL,    @vlbaseicm,     @vldesconto,      0,    NULL,   @vlfrete,  @vlicm,  @vlicmret,  0,   @vlmercad, 0,      0,  @vlentrada,    NULL,    .01,  2,     0,   @codfil,     0,   NULL,  0,   @vloutras, NULL,  NULL,  NULL,   0,   @vltotal,  NULL,   NULL,  NULL,  NULL,  @peso, @vlbaseicmssub, 0,   NULL,   NULL,   NULL,   NULL,   NULL,  NULL,  NULL, NULL, NULL,    0,      NULL,   NULL,   0,     NULL,    NULL,      0,     NULL,   @hrhora ,      NULL,     NULL,  NULL,   3,  @endfat,   'N',     0,    NULL,      0,      0,      0,     @hrhora,     'S',   NULL,    NULL,   NULL, NULL,  0,     NULL,  NULL,    NULL,     0,       0,      0,       NULL,    NULL,    NULL,   NULL,   NULL,   NULL,   NULL,   NULL,  'AC12',  @cliente,             0,    NULL,  @coduser,    0,       0,      0,  @qtprc, @vlprc,   0,    NULL,   NULL,   NULL,   NULL,  @identproc, @codnatop,    NULL,     NULL,     0,    NULL,      NULL,        0,      NULL,   NULL,    NULL,   0,    'C',     '0',     NULL,   NULL,   NULL,  NULL,    0,       0,         0,        NULL,       0,        0,       NULL,  @vlbaseicmd , @vlicmd,  0,       'N',   0,     'N',    0,        0,       0,      0,      NULL,     1,    'N',     0,     0,      NULL,    0,    NULL,     0,       0,       0,          0,    0,    0,    0,      0,     NULL,     NULL,      0,       0,   @modelonf,    0,        0,    0,    NULL,     NULL,      NULL,      NULL,    NULL,  NULL,  @statusnfe,      NULL,    NULL,  NULL,  @dtnota ,   NULL,      NULL,       NULL,    NULL,  @codnatopdifcompl,   0,      0,      0,      0,      0,     0,      0,   NULL,  NULL,    @DATAHORAUTC ,    NULL,      0,    NULL,   NULL,    NULL,   NULL,   NULL,    NULL,     @chave,                   NULL,         NULL,       NULL,    NULL,     NULL,    NULL,       NULL,    0,     0,    0,     0,     0,      2,      NULL,    NULL,     NULL,    NULL,      NULL,         NULL,        0,      @vlbasecbs, @vlcbs,  @vlbaseibs,   @vlibs,    @vlbaseibsmun,     @vlibsmun,    0,     0,    0 ,    'F'    , 'N',           'S'    )


   --exec SP_FIKON_INTEGRA_MOV_ITSAIDA @numpedven, @numnota,@serie,@codfil ,@codcli,@hrhora, @estado


 END TRY

 BEGIN CATCH

	rollback

    DECLARE @Mensagem NVARCHAR(MAX);

    SET @Mensagem =
        'Erro ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) +
        ' na linha ' + CAST(ERROR_LINE() AS VARCHAR(10)) +
        ': ' + ERROR_MESSAGE();

    THROW 50000, @Mensagem, 1;

	  IF CURSOR_STATUS('global','CR_INSERE') >= -1
    BEGIN
        CLOSE CR_INSERE;
        DEALLOCATE CR_INSERE;
    END

 END CATCH

 commit
GO

SET NOEXEC OFF;
GO

-- Conferência: as duas procedures devem aparecer com a data de hoje.
SELECT name, modify_date FROM sys.objects
 WHERE name IN ('SP_FIKON_NOTA_GRAVAR_FINANCEIRO', 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA',
                'SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_SCRIPT07', 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT07')
 ORDER BY name;
GO
