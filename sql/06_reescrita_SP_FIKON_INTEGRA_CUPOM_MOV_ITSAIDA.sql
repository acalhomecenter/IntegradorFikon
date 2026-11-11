/*
  06 - Reescrita da dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA (itens do cupom FIKON)  -  10/11/2026

  Problema (notas 84 e 85, filial 15, série 444, dev DB-TREINO):
    O cabeçalho do cupom (MOV_SAIDA.VLTOTAL) ficava NULL mesmo depois do script 05.
    Causa: esta procedure declara @vltotal e NUNCA dá valor a ele. O item era gravado com
    VLTOTAL e VLTOTITEM nulos na MOV_ITSAIDA; no fim ela somava o VLTOTAL dos itens (NULL) e
    gravava essa soma no cabeçalho, apagando o total que a SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA tinha
    gravado. No dev havia 4 cupons com item sem total, desde 25/09/2026.

  O que muda (o resto da procedure fica igual ao original):
    1. Total do item: @vltotal = (@qtcomp * @precounit) - @vldescitem, antes do INSERT do item.
       Pela ApiAcal isso dá exatamente o "total" do produto no payload da FIKON.
       Vai para MOV_ITSAIDA.VLTOTAL e MOV_ITSAIDA.VLTOTITEM (as duas colunas já usavam @vltotal).
    2. Total do cabeçalho: só atualiza MOV_SAIDA.VLTOTAL se a soma dos itens não for nula.
    3. Nota não encontrada pela chave: antes seguia com tudo nulo e gravava o item assim mesmo;
       agora dá erro.
    4. Cliente e hora do item: @codcli e @hrhora eram declarados e nunca preenchidos (item ficava
       com CODCLI e HRHORA nulos); agora vêm do cabeçalho da nota (MOV_SAIDA), como os demais campos.

  Não alterado (só registro, para avaliar depois):
    - O LEFT JOIN de trib3 (ICMS ST, TPIMP 'S') compara as colunas de trib2; na prática trib3 nunca
      é encontrado e ALIQICMSUB vai 0.
    - @estado nunca é preenchido; os IFs de natureza de operação por estado não entram e ficam
      os valores iniciais (540 / 5).
    - O texto da OBSFISCAL tem "TRIBUT RIA" (com espaço) no original; foi mantido igual.

  Como rodar: no SSMS, conectado no servidor certo e no banco dbgemco, executar o script INTEIRO (F5).
    - O 1º bloco guarda a versão atual como SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT06.
      Se a cópia não puder ser feita, o script para (SET NOEXEC ON) e nada é alterado.
    - Depois vem o ALTER PROC completo.
  Para voltar atrás: abrir a _BKP_SCRIPT06, trocar o nome pelo original e executar como ALTER.

  Corrigir os cupons já gravados sem total (ex.: 84 e 85) é outro passo: o script abaixo só vale
  para os próximos.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Cópia de segurança ===================== */
DECLARE @def nvarchar(max);

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT06') IS NULL
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA'));
    IF @def IS NOT NULL AND @def LIKE N'%PROC%[[]dbo].[[]SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]%'
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]', N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT06]');
        EXEC sys.sp_executesql @def;
    END
END

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT06') IS NULL
BEGIN
    RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
    SET NOEXEC ON;   -- o bloco seguinte não é executado
END
ELSE
    PRINT 'Copia guardada: SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT06.';
GO

/* ===================== 2. SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA ===================== */
ALTER PROC [dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]
 @chavenfe varchar(44),
 @coditprod numeric(12),
 @qtcomp numeric(15,2),
 @precounit numeric(15,2),
 @vldescitem numeric(15,5)

as

-- Reescrita em 10/11/2026 (script 06_reescrita_SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA.sql). Ver o cabeçalho do script.

BEGIN TRY

declare @numnota numeric(12,0)
declare @serie varchar(3)
declare @codfil int
declare @codcli numeric(12,0)
declare @hrhora datetime
declare @estado varchar(2)
declare @numpedven numeric(12,0) = 999999
declare @dtnota date = getdate()
declare @dtemissao date = getdate()
declare @dtpedido date
declare @dtentrega date = getdate()
declare @condpgto  varchar(3)
declare @codvendr int
declare @endcob int
declare @endent int
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
declare @vltotal numeric(15,2)
declare @vlbaseicmssub numeric(15,2)
declare @endfat int
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
declare @modelonf varchar(4)='55'
declare @DATAHORAUTC varchar(50) = FORMAT(SYSDATETIMEOFFSET(), 'yyyy-MM-ddTHH:mm:sszzz');
declare @vlbasecbs numeric(15,2)
declare @vlaliqcbs numeric(15,2) = .9
declare @vlcbs numeric(15,2)
declare @vlbaseibs numeric(15,2)
declare @vlaliqibs numeric(15,2) =.1
declare @vlibs numeric(15,2)
declare @vlbaseibsmun numeric(15,2)
declare @vlibsmun numeric (15,2)
declare @tpnota varchar(4)
declare @item int
declare @aliqicm  numeric(15,2)
declare @ALIQICMSUB numeric(15,2)
declare @DPI numeric(11,9)
declare @UNEMBAL varchar(2)
declare @cmup numeric(15,4)
declare @codsitprod varchar(2)
declare @QTESTOQUE numeric(9,3)
declare @vldescitemrat numeric(15,5)
declare @qtemb numeric(4,0)
declare @VLOUTRASF numeric(22,9)
declare @obsfiscal varchar(180)= 'ICMS PAGO POR SUBST. TRIBUT RIA CONFORME ART. 559 DO DECRETO 24.569/97 DO RICMS/CE'
declare @ctf numeric(2,0)
declare @cmupi numeric(15,4)
declare @cue numeric(15,4)
declare @CODBARRA numeric(14,0)
declare @vlbaseicmsefetivo numeric(15,2)
declare @vlicmsefetivo numeric(15,2)
declare @fisico numeric(9,3)
declare @resfis numeric(9,3)
declare @cubagem numeric(8,4)
declare @filorig int = @codfil
declare @qtcompbaixa numeric(9,3)
declare @totalPedido numeric(15,2)
declare @totalPeso numeric(12,3)
declare @aliqicmred numeric(15,2)

set @coditprod = LEFT(@coditprod, LEN(@coditprod) - 1)

--Pegando variaveis que estao na mov_saida (cliente e hora incluídos: antes ficavam nulos no item)
select @filorig=codfil, @codfil=codfil, @codvendr = codvendr, @numnota = NUMNOTA , @serie = SERIE, @tpnota = tpnota, @dtnota = dtnota,
       @codcli = CODCLI, @hrhora = HRHORA
  from dbgemco..mov_saida where CHAVENFE=@chavenfe

IF @codfil IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: nota com a chave %s nao encontrada na MOV_SAIDA.', 16, 1, @chavenfe);
END

set @item = (select count(*)+1 from dbgemco..mov_itsaida where codfil = @codfil and numnota=@numnota and tpnota = @tpnota and serie=@serie and dtnota=@dtnota)

 DECLARE CR_INSERE_ITENS CURSOR FOR

select isnull(trib.ALIQUOTA,0) as ALIQICM, isnull(trib3.ALIQUOTA,0) as aliqicmsub,  isnull(trib2.ALIQUOTA,0) as ALIQICMRED,
0 as cubagem,
emb.UNIDMENOR,
pco.CODSITPROD,
cus.CMUP,
cus.CMUPI,
cus.CUE,
bar.CODBARRA,
pro.PESOUNIT
from CAD_ITPROD itp inner join CAD_PROD pro on
itp.CODPROD=pro.CODPROD
inner join CAD_CODBARRA bar on
bar.CODPROD=pro.CODPROD
and bar.CODEMBAL=0
and bar.TSULTALT = (select MAX(TSULTALT) from dbgemco..CAD_CODBARRA where CODPROD=pro.CODPROD and CODEMBAL=0)
inner join CAD_PRECO pco on
pco.CODFIL=8
and pco.CODITPROD=itp.CODITPROD
and pco.CODEMBAL=0
inner join VEN_PRODFIL cus on
cus.CODFIL=8
and cus.CODPROD=pro.CODPROD
inner join CAD_EMBAL emb on
emb.CODPROD=pro.CODPROD
and emb.CODEMBAL=0
left join dbgemco..CAD_IMPTRIBUT(nolock) trib on
trib.CODIMP = pro.CODICMS and trib.TPIMP = 'I'
and trib.ESTDEST = 'CE' and trib.ESTORIG = 'CE'
and trib.CODGRPTPNOTA = 2
left join dbgemco..CAD_IMPTRIBUT(nolock) trib2 on
trib2.CODIMP = pro.CODICMRED and trib2.TPIMP = 'R'
and trib2.ESTDEST = 'CE' and trib2.ESTORIG = 'CE'
and trib2.CODGRPTPNOTA = 2
left join dbgemco..CAD_IMPTRIBUT(nolock) trib3 on
trib2.CODIMP = pro.CODICMRED and trib2.TPIMP = 'S'
and trib2.ESTDEST = 'CE' and trib2.ESTORIG = 'CE'
and trib2.CODGRPTPNOTA = 2
where itp.CODITPROD=@coditprod


  OPEN CR_INSERE_ITENS
	  FETCH NEXT FROM CR_INSERE_ITENS INTO @aliqicm,@ALIQICMSUB,@aliqicmred,@cubagem,@UNEMBAL,@codsitprod,@cmup,
	  @cmupi,@cue,@codbarra,@peso

	     WHILE @@FETCH_STATUS = 0

		 BEGIN

		 --@vlbaseicm,@vlicm, @vlbaseicmssub,@vlicmret,@vldescitem,@vldescitemrat,@qtemb,@vltotal,@ctf

		 set @ctf = 90

		 -- Total do item (antes @vltotal nunca era preenchido e o item ia com VLTOTAL/VLTOTITEM nulos)
		 set @vltotal = ROUND((@qtcomp * @precounit) - ISNULL(@vldescitem, 0), 2)

		 set  @fisico  = (select fisico from cad_prodloc where codfil=@filorig and coditprod=@coditprod)
		 set  @resfis  = (select resfis from cad_prodloc where codfil=@filorig and coditprod=@coditprod)
		 set  @qtcompbaixa = @qtcomp*-1
		 set @qtestoque = @fisico

		 if ((@ctf=60 or @ctf=90) and @estado='CE' )
		    begin
				set @codnatop = 540
				set @codnatopdifcompl = 5
				set  @obsfiscal = 'ICMS PAGO POR SUBST. TRIBUT RIA CONFORME ART. 559 DO DECRETO 24.569/97 DO RICMS/CE'
			end

		 if ( @ctf=60  and @estado <> 'CE' )
		    begin
				set @codnatop = 640
				set @codnatopdifcompl = 4
				set  @obsfiscal = 'ICMS PAGO POR SUBST. TRIBUT RIA CONFORME ART. 559 DO DECRETO 24.569/97 DO RICMS/CE'
			end

         	 if ( @ctf=90  and @estado <> 'CE' )
		    begin
				set @codnatop = 610
				set @codnatopdifcompl = 8
				set  @obsfiscal = 'ICMS PAGO POR SUBST. TRIBUT RIA CONFORME ART. 559 DO DECRETO 24.569/97 DO RICMS/CE'
			end
			   --else
			   --  begin
					 --set @codnatop = 540
					 --set @codnatopdifcompl = 5
					 --set  @obsfiscal = ''
			   --  end

           if (@serie='1')
		      begin

			  set @modelonf = '55'

			  end
				else
				  begin
					 set @modelonf = '65'

				  end

INSERT INTO MOV_ITSAIDA (CODFIL,  TPNOTA,  NUMNOTA,    DTNOTA,   SERIE,   CODITPROD,  ITEM,  QTCOMP,  PRECORDZ, PRECOUNIT,  ALIQICM,   ALIQICMSUB, ALIQICMRED, VLIPI, LOCAL, TPDEPOS, PORCIPI, MINUTA,    CUBAGEM, CODASSTEC, DTASSTEC, CODEMBAL,  DPI,    DESCCOMPLE, STATUS,  NUMPEDVEN,  UNEMBAL,  CODCLI,   QTRETORN, PRECJUR, VLFRETE,    QTDEVOL,    PRECOUNITLIQ, VLSUPINF, FLINTEGRACAO, CMUP, MEDGER, HRHORA,  CODSITPROD,   RUA, BLOCO, APTO,  FILPED,   DTPROD, ALIQICMSUBUF, FILORIG,   IDADEPROD, VLBASEICMS,      VLISENTO, VLNTRIBUT, VLOUTRAS,     VLICM,    QTESTOQUE, VLBASEICMSSUB,     VLICMRET,     VLDESCITEM,     VLDESCITEMRAT,   QTSALDO, CODPROM,    QTEMB, VLBASEICMSF, VLISENTOF, VLNTRIBUTF,  VLOUTRASF,   VLICMF, VLBASEICMSSUBF, VLICMRETF, ALIQIRF, VLDESPACES, VLOUTDESP, VLOFERTA, COMPLEMENTO, CRM, VLOUTRASIPI, VLBASEIPI, VLISENTOIPI, FLBXCOMP, QTCONSIG, QTVOLUME, CODITPRODKIT, COMISSPER, COMISSVAL, FLPRODGEN, CODVENDR,     DTVALIDFIM, DTVALIDINI, VLISS,   CODNATOP, CODNATOPDIF,    CODNATOPCOMPL,   CODNATOPDIFCOMPL,       OBSFISCAL, CUEORIG, FLDETALHE, VLTOTITEM,   CTF,   CODPLANOSERV, ALIQICMSFRETE, VLFRETERAT,VLICMSFRETE, VLDESPFIN, VLICMRETFRT, VLSEGURO, VLDESPRAT, VLTOTAL,   CMUPI,  VLTOTIPI, FILPEDARMAZEM, NUMPEDARMAZEM,TIPOPEDARMAZEM, VLBASEICMSUBENT, VLICMRETENT, VLIRRF, DTALTERACAO, USERIDALT, CUE, VLTOTBASEIPI, FLLOTEVENCTO,CODPRESTSERV, DESCPRESTSERV, FLPRODPROCESS, VLJUROSVENDA, VLJUROSFIN, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV,VLBASEICMD,     VLICMD,     PRECOLISTA, ALIQPISCOFINSCSLL,VLPISCOFINSCSLL, PENCARGO, VLJUROS, VLBASEISS, ALIQISS, PRECOORIG, VLDESCNOTA, ALIQICMREPI, VLBASEICMORIGREPI, VLICMORIGREPI,VLICMREPI, ALIQPISSUB, ALIQCOFSUB, VLPISSUB, VLCOFSUB, FLSUBSTINTERNA, QTVENDAKIT, PCONTSOC, VLPPIS, VLPCONTSOC,PPIS, ALIQICMDIF, VLBASEICMDIF, VLICMDIF, VLICMDESCONTOF, VLTAC, CODTECNICO, VLPISDESCONTOF, VLCOFDESCONTOF, ALIQICMDIFSAI, VLBASEICMSDIFSAI, VLICMDIFSAI, NUMORC, CUSTOGER, ALIQICMSATIVO, VLBASEICMSATIVO, VLICMSATIVO, FLATUTRAN, FLPREINDIG, VLPISRET, VLCSLLRET, VLIRRET, VLCOFINSRET, ALIQPCTM, ALIQICMREDUF, VLNTRIBUTD, DESCUNIDTRIBUTAVELNF, FATORCONVTRIBUTAVELNF, VLICMRETV, ALIQICMCREDITO,  VLICMCREDITO, ORIGEMPROD, DESCLICITACAO, ALIQIBPT, VLIBPT, VERSAOIBPT, NUMFCI, CONVERSAO, VLCUSTOIMP, OBSCOMPLPROD, FLESCFISCALDIF, CFOPNOTA, CTFNOTA, CODJUST, CHAVEIBPT, FONTEIBPT, ALIQIBPTEST, VLIBPTEST, ALIQIBPTMUN, VLIBPTMUN,VLICMSRECUPTRANSF, ALIQICMUF, VLICMSSTRECUPTRANSF,  ALIQFECEP , ALIQICMPART, VLFECEPF, VLFECEP,  VLFECEPSTF, VLFECEPST, VLICMPARTUFF, VLICMPARTUF, VLICMPARTF, VLICMPART, FLFECEPADIC, CEST, VLBASEPIS, VLBASECOFINS, CUETRANSF, CMUPTRANSF,CSTIPI, CSTPIS, CSTCOFINS, CODBARRA, VLBASEFECEPF, VLBASEFECEPSTF, ALIQFECEPST, VLBASEICMPARTUFF,  CODIGO53, VLAJUSTEITEM, CODIGO52, CODIGO56, VLBASESTRETANT, VLICMSTRETANT, VLREMGST, VLBASEFCPSTRETANT, ALIQFCPSTRETANT, VLFCPSTRETANT,VLBASEICMSEFETIVO,     VLICMSEFETIVO,  VLICMSGARANTIDO, VLBASEICMSGARANTIDO, VLICMEG, VLBASEICMEG, VLSUBSTITUTOSTRETANT,  VLICMOPERACAO, ALIQICMDIFERIMENTO, VLICMDIFERIDO, VLICMSDESON, CODMOTDESICMS,VLFECEPSTGARANTIDO, VLBASEDESONDIFERF, VLBASEICMUE, VLICMUE, VLBASEICMSSTUE, VLICMSSTUE, VLFECEPSTUE, VLBASEICMMUP, VLICMMUP, VLBASEICMSSTMUP, VLICMSSTMUP, VLFECEPSTMUP, VLICMOPERSTF,      VLFECEPOPERSTF, VLFECEPUE, VLFECEPMUP, VLNTRIBUTUF, VLDESCBASEPIS, VLDESCBASECOFINS, CUSTORE, CUE_RE6763, CMUP_RE6763, VLCASHBACKPROFISCONSTRU, CODITPRODBENEF, CLASTRIBCBS, CLASTRIBIBS, CLASTRIBIS, CSTCBS, CSTIBS, CSTIS,  VLBASECBS,     ALIQCBS,    VLCBS, VLBASEIBS,          ALIQIBS,          VLIBS,  VLBASEIBSMUN,            ALIQIBSMUN, VLIBSMUN, VLBASEIS, ALIQIS, VLIS, PERCREDUTOR  )
VALUES (                 @codfil, @tpnota, @numnota, @dtnota,    @serie, @coditprod,  @item, @qtcomp,   NULL,  @precounit,  @aliqicm,  @ALIQICMSUB,        0,         0,    1,     'L',       0,     NULL,  @cubagem,       NULL,     NULL,     0,      @dpi,       NULL,     2,     @numpedven, @UNEMBAL, @codcli,    NULL,      0,      @vlfrete,     0,         @precounit,   0,         NULL,    @cmup,    0,   @hrhora, @codsitprod,  NULL, 0,    NULL,   @codfil,   NULL,     20,        @codfil,     NULL,   @vlbaseicm,           0,        0,    @vloutras,    @vlicm,   @QTESTOQUE,   @vlbaseicmssub,    @vlicmret,  @vldescitem,   @vldescitemrat,      0,       0,     @qtemb,       0,            0,        0,     @VLOUTRASF,     0,          0,            0,       0,         0,          0,       0,          NULL,     0,       0,           0,         0,       NULL,      0,        0,          NULL,        NULL,      NULL,      NULL,    @CODVENDR,      NULL,       NULL,       0,    @codnatop,      NULL,   @codnatopdifcompl, NULL,                 @obsfiscal,    NULL,    NULL,    @vltotal,   @ctf,    NULL,               0,           0,         0,           0,      NULL,         0,        0,       @vltotal, @cmupi,    0,         NULL,         NULL,           NULL,            NULL,          NULL,       0,       NULL,      NULL,  @cue,      0,            'N',          0,           NULL,           'N',           NULL,         0,             0,              0,           @vlbaseicmd,   @vlicmd,     0,             0,                0,             0,        0,        0,        0,   @precounit,    0,             0,             0,              0,         0,           0,           0,        0,          0,         NULL,          0,        0,       0,        0,       0,      0,          0,             0,         0,         0,        0,             0,            0,                0,             0,               0,       0,      NULL,        0,              0,             0,          NULL,       'N',       0,        0,         0,        0,          0,        0,            0,                NULL,                 NULL,            0,             0,              0,          0,           NULL,        NULL,  NULL,     NULL,      NULL,    1,        NULL,           NULL,         NULL,         0,      NULL,    NULL,    NULL,      NULL,       NULL,         NULL,      NULL,        NULL,      NULL,         @aliqicm,        NULL,                0,          0,         0,          0,        0,         0,          0,             0,         0,           0,         'N',     NULL,      0,         0,        NULL,       NULL,     NULL,  NULL,    NULL,   @CODBARRA,      0,            0,              0,            0,              NULL,      NULL,        NULL,    NULL,          0,           0,             0,             0,                0,               0,       @vlbaseicmsefetivo, @vlicmsefetivo,      NULL,                NULL,          NULL,     NULL,                0,              NULL,            NULL,               NULL,         NULL,       NULL,             NULL,           NULL,               0,        0,            0,            0,          0,          0,           0,           0,             0,           0,      @vlicmsefetivo,          0,             0,           0,           0,          0,                0,          0,          0,          0,                  0,                   0,        '000001',   '000001',       NULL,   '000', '000',   NULL, @vlbasecbs,   @vlaliqcbs,  @vlcbs,     @vlbaseibs,      @vlaliqibs,      @vlibs,       @vlbaseibsmun,          0,         0,         0,      0,     0,        0)


UPDATE MOV_ITPED  WITH (READCOMMITTED) SET   DTNOTA =  @dtnota, QTEMITIDO =  @qtcomp, STATUS =  6, NUMNOTA =  @numnota, TPNOTA =  @tpnota, QTFAT =  QTFAT + @qtcomp, QTLIB =  QTLIB - @qtcomp, QTCORTE =  case when qtcorte> 0 then QTCORTE - @qtcomp else 0 end  WHERE 1=1 AND MOV_ITPED.CODFIL = @codfil AND MOV_ITPED.NUMPEDVEN = @numpedven AND MOV_ITPED.TIPOPED = 0 AND MOV_ITPED.CODITPROD = @coditprod AND MOV_ITPED.ITEM = @item

exec SPU_PROLOCI 1, @codfil, 'L', @coditprod, @qtcompbaixa, @qtcompbaixa, 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0

INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,    FISICO,  RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO,    FISICOPOS,         RESFISPOS,       ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG,  DTPROC,           ROTINA,                  COMANDOSQL,                                                                                                                                                                                   IDENTPROC )
VALUES ( @codfil, @numpedven,@numnota, GETDATE(),@tpnota,                   'S',     3,    @coditprod, @fisico,  @resfis,     0,         0,      0,       0,      0,         0,           0,       -@qtcomp,      'FISICO;RESFIS;', 'N',   @fisico-@qtcomp,  @resfis-@qtcomp ,         0,           0,         0,        0,           0,              0,             0,         @codfil, getdate(), 'GRAVAITENSNOTAFISCAL', '{CALL SPU_PROLOCI(1, '+convert(varchar,@codfil)+', L, '+convert(varchar,@coditprod)+', -'+convert(varchar,@qtcomp)+', -'+convert(varchar,@qtcomp)+', 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0)} ',                                    'INTEGRADOR FIKON' )




     FETCH NEXT FROM CR_INSERE_ITENS INTO  @aliqicm,@ALIQICMSUB,@aliqicmred,@cubagem,@UNEMBAL,@codsitprod,@cmup,
	  @cmupi,@cue,@codbarra,@peso



  END

  CLOSE CR_INSERE_ITENS
  DEALLOCATE CR_INSERE_ITENS

 set @totalPedido =  (Select sum(vltotal) from mov_itsaida  where codfil = @codfil and numnota=@numnota and tpnota = @tpnota and serie=@serie and dtnota=@dtnota)

 -- Só grava o total no cabeçalho se a soma existir (nunca apaga com NULL).
 IF @totalPedido IS NOT NULL
     UPDATE MOV_SAIDA SET VLtotal= @totalPedido where chavenfe=@chavenfe



  END TRY

  BEGIN CATCH


    DECLARE @Mensagem NVARCHAR(MAX);

    SET @Mensagem =
        'Erro ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) +
        ' na linha ' + CAST(ERROR_LINE() AS VARCHAR(10)) +
        ': ' + ERROR_MESSAGE();

    THROW 50000, @Mensagem, 1;

	  IF CURSOR_STATUS('global','CR_INSERE_ITENS') >= -1
    BEGIN
        CLOSE CR_INSERE_ITENS;
        DEALLOCATE CR_INSERE_ITENS;
    END

  END CATCH
GO

SET NOEXEC OFF;
GO

-- Conferência: a procedure e a cópia devem aparecer.
SELECT name, modify_date FROM sys.objects
 WHERE name IN ('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA', 'SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT06')
 ORDER BY name;
GO
