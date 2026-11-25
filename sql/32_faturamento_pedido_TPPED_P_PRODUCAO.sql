/*
  32 - Faturamento FIKON por pedido: itens TPPED 'P' (pedido normal da loja) - PRODUÇÃO  -  23/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  (O DEV não estava acessível ao gerar este script; a versão do DEV será conferida à parte.)
  IMPORTANTE: rodar ANTES de publicar o Integrador Fikon que passa a aceitar TPPED 'P'.

  Problema (NF-e 4 série 2 da DM, pedido FIKON 2093021, pedido Gemco 14259079):
    "não tem itens liberados para faturar (STATUS 5, FLLIBFAT S, TPPED R)".
    Os 6 itens do pedido estão com TPPED 'P'. No Gemco da DM o 'P' é o pedido normal da loja faturado em NF-e
    (4.777 itens faturados assim desde outubro, contra 1.121 com 'R'). A SP_FIKON_INTEGRA_MOV_ITSAIDA só
    faturava 'R' (o caso da filial 502).

  O que muda (procedure completa abaixo):
    1. Cursor dos itens: TPPED 'R' ou 'P'. Continua só STATUS 5, FLLIBFAT 'S' e FILORIG = filial da nota:
       item de outra filial (ex.: depósito 5) sai na nota daquela filial, como no Gemco. No pedido 14259079 a
       NF-e da filial 15 leva os 4 itens da loja; os 2 do depósito ficam para a nota da filial 5.
    2. Total (VLTOTAL) da nota = itens faturados NESTA nota (antes: todos os 'R' do pedido).
    3. Peso por item (antes: todos os 'R' do mesmo produto).
    4. Pedido parcial (STATUS 8) enquanto restar item não faturado e não cancelado; senão faturado (6).
       Antes: "existe item com TPPED <> 'R'".
    5. Nenhum item faturável: erro, em vez de deixar a nota sem itens.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
    - O bloco 1 confere a versão da procedure (SHA-256 4EED4F4F...) e guarda a cópia
      SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT32. Se algo estiver diferente, nada é alterado.
  Para voltar atrás: abrir a cópia _BKP_SCRIPT32, trocar o nome pelo original e executar como ALTER.
  Depois: publicar o Integrador; a NF-e 4 série 2 do pedido 14259079 é gravada no próximo ciclo.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA'));

IF @def IS NULL
   OR (HASHBYTES('SHA2_256', @def) <> 0x4EED4F4FF63BDDA6EEE7C78A28238F72E1A9A2FFFEE17F491D737FE0D8E4D347 AND CHARINDEX(N'script 32', @def) = 0)
BEGIN
    RAISERROR('Nada foi alterado: SP_FIKON_INTEGRA_MOV_ITSAIDA nao existe ou esta numa versao diferente da esperada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT32') IS NULL
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_INTEGRA_MOV_ITSAIDA]', N'[dbo].[SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT32]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT32') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copia guardada: SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT32.';
END
GO

/* ===================== 2. SP_FIKON_INTEGRA_MOV_ITSAIDA (completa) ===================== */
ALTER PROC [dbo].[SP_FIKON_INTEGRA_MOV_ITSAIDA] 


 @numpedven numeric(12,0),
 @numnota numeric(12,0),
 @serie varchar(3),
 @codfil int,
 @codcli numeric(12,0),
 @hrhora datetime ,
 @estado varchar(2)

as

-- script 32 (23/11/2026): fatura tambem item TPPED 'P' (pedido normal da loja, faturado em NF-e no Gemco;
-- ex.: DM, filial 15). Continua so STATUS 5, FLLIBFAT 'S' e FILORIG = filial da nota (item de outra filial,
-- ex.: deposito 5, sai na nota daquela filial, como no Gemco). Total e peso da nota pelos itens faturados
-- nela; pedido parcial (8) enquanto restar item nao faturado e nao cancelado; erro se nenhum item entrar.

BEGIN TRY 

declare @dtnota date = getdate()
declare @qtd_itens_s32 int = 0   -- script 32: itens gravados nesta nota
declare @dtemissao date = getdate()
declare @dtpedido date
declare @dtentrega date
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
declare @coditprod numeric(10,0)
declare @item int
declare @qtcomp numeric(9,3)
declare @precounit numeric(15,2)
declare @aliqicm  numeric(15,2)
declare @ALIQICMSUB numeric(15,2)
declare @DPI numeric(11,9)
declare @UNEMBAL varchar(2)
declare @cmup numeric(15,4)
declare @codsitprod varchar(2)
declare @QTESTOQUE numeric(9,3)
declare @vldescitem numeric(15,5)
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

 DECLARE CR_INSERE_ITENS CURSOR FOR

 SELECT MOV_ITPED.CODVENDR, mov_itped.tpnota, MOV_ITPED.CODITPROD ,  MOV_ITPED.ITEM, 
  MOV_ITPED.QTCOMP, MOV_ITPED.PRECOUNIT, MOV_ITPED.ALIQICM, MOV_ITPED.ALIQICMSUB,
  MOV_ITPED.CUBAGEM, MOV_ITPED.DPI, CAD_EMBAL.UNIDMAIOR,MOV_ITPED.VLFRETE,MOV_ITPED.CMUP,
  MOV_ITPED.CODSITPROD,mov_itped.VLBASEICMS, mov_itped.VLICM,MOV_ITPED.VLBASEICMSSUB, MOV_ITPED.VLICMRET,
  MOV_ITPED.VLDESCITEM, MOV_ITPED.VLDESCITEMRAT, MOV_ITPED.QTEMB,(mov_itped.VLTOTITEM+MOV_ITPED.VLFRETE-MOV_ITPED.VLDESCITEMRAT),
  MOV_ITPED.CTF, VEN_PRODFIL.CMUPI , VEN_PRODFIL.CUE,MOV_ITPED.CODBARRA,
  ((mov_itped.VLTOTITEM+MOV_ITPED.VLFRETE-MOV_ITPED.VLDESCITEMRAT) - mov_itped.VLICM - ((((mov_itped.VLTOTITEM+MOV_ITPED.VLFRETE-MOV_ITPED.VLDESCITEMRAT)-mov_itped.VLICM) * 9.25)/100))/qtcomp as VLBASE
 --CAD_PROD.CODPROD, CAD_PROD.CODICMS, CAD_PROD.CODICMSUB, CAD_PROD.CODICMRED, CAD_PROD.CTF,
 --MOV_ITPED.TPNOTA,
 --MOV_ITPED.CODEMBAL, MOV_ITPED.QTEMB, CAD_EMBAL.UNIDMAIOR,  CAD_EMBAL.UNIDMENOR,  CAD_EMBAL.CONVERSAO, 
 --MOV_ITPED.ALIQICMRED,
 --MOV_ITPED.ALIQICMSUBUF, MOV_ITPED.VLIPI,  
 --MOV_ITPED.LOCAL,  MOV_ITPED.TPDEPOS, 
 --MOV_ITPED.FILORIG, MOV_ITPED.PORCIPI , 
 --MOV_ITPED.DPI, MOV_ITPED.PESO, 
 --MOV_ITPED.VLFRETE, MOV_ITPED.PRECOUNITLIQ, MOV_ITPED.CMUP, 
 --MOV_ITPED.VLDESCITEM, MOV_ITPED.VLDESCITEMRAT, 
 --MOV_ITPED.QTVOLUME,    MOV_ITPED.VLTOTITEM, MOV_ITPED.CMUPI,  CAD_PROD.PESOLIQ, MOV_ITPED.CTF, 
 --MOV_ITPED.CUBAGEM , CAD_PROD.DIFER, MOV_ITPED.TIPOPED, MOV_ITPED.CUE, CAD_PROD.PESOUNIT,
 --MOV_ITPED.VLTOTBASEIPI, MOV_ITPED.VLBASEICMSSUB, MOV_ITPED.VLICMRET, MOV_ITPED.VLOUTRAS, CAD_PROD.FLLOTEVENCTO, MOV_ITPED.FLLOTEVENCTO, 
 --CAD_FAMILIA.DESCRICAO,  CAD_PROD.FLICMSG, MOV_ITPED.PRECOORIG, MOV_ITPED.ALIQPISSUB, MOV_ITPED.ALIQCOFSUB, MOV_ITPED.VLPISSUB, MOV_ITPED.VLCOFSUB, MOV_ITPED.QTFAT, MOV_ITPED.FLLIBFAT, 
 --MOV_ITPED.DTENTREGA , VEN_PRODFIL.CMUP, VEN_PRODFIL.CMUPI , VEN_PRODFIL.CUE, VEN_PRODFIL.VLBASEICMSUB, VEN_PRODFIL.VLICMRET , VEN_PRODFIL.CUEI, VEN_PRODFIL.CUSTONF, VEN_PRODFIL.TABELA , VEN_PRODFIL.CUSTTAB,
 -- CAD_PROD.NCM, CAD_PROD.ALIQIBPTIMP, CAD_PROD.ALIQIBPTNAC, CAD_PROD.VERSAOIBPT, CAD_ITPROD.DIGITPROD,  MOV_ITPED.CODJUST, MOV_ITPED.VLJUROS,CAD_ITPROD.CODLINHA, CAD_ITPROD.CODFAM, CAD_ITPROD.CODITPROD , MOV_ITPED.TPPED
 FROM CAD_PROD, CAD_ITPROD, CAD_EMBAL, CAD_FAMILIA, CAD_ESPEC, CAD_COR , 
  VEN_PRODFIL, MOV_ITPED, CAD_FILIAL   
 WHERE 1=1 AND 1=1 
 AND VEN_PRODFIL.CODFIL  = CAD_FILIAL.CODFILCUST 
 AND CAD_FILIAL.CODFIL = MOV_ITPED.FILORIG 
 AND CAD_FILIAL.CODFIL = MOV_ITPED.FILORIG 
 AND VEN_PRODFIL.CODPROD  =  CAD_ITPROD.CODPROD 
 AND MOV_ITPED.CODITPROD = CAD_ITPROD.CODITPROD  
 AND CAD_ITPROD.CODPROD  = CAD_PROD.CODPROD  
 AND CAD_PROD.CODPROD = CAD_EMBAL.CODPROD  
 AND MOV_ITPED.CODEMBAL = CAD_EMBAL.CODEMBAL 
 AND CAD_ITPROD.ESPECIFIC = CAD_ESPEC.ESPECIFIC  
 AND CAD_ITPROD.CODCOR = CAD_COR.CODCOR  
 AND CAD_ITPROD.CODFAM = CAD_ESPEC.CODFAM  
 AND CAD_ITPROD.CODFAM = CAD_FAMILIA.CODFAM  
 AND MOV_ITPED.CODFIL = @codfil 
 AND MOV_ITPED.TIPOPED = 0 
 AND MOV_ITPED.NUMPEDVEN = @numpedven 
 --AND  (MOV_ITPED.STATUS = 4 OR MOV_ITPED.STATUS = 5 OR MOV_ITPED.STATUS = 8) AND MOV_ITPED.QTLIB > 0 
 AND MOV_ITPED.FLLIBFAT = 'S' 
 AND MOV_ITPED.FILORIG = @filorig
 and MOV_ITPED.TPPED IN ('R', 'P')   -- script 32: antes so 'R'
  and MOV_ITPED.STATUS=5
 order by mov_itped.ITEM

  OPEN CR_INSERE_ITENS
	  FETCH NEXT FROM CR_INSERE_ITENS INTO  @codvendr,@tpnota, @coditprod, @item, @qtcomp,@precounit,@aliqicm, @ALIQICMSUB,@cubagem,@dpi,@UNEMBAL,@vlfrete,@cmup,@codsitprod,
	  @vlbaseicm,@vlicm, @vlbaseicmssub,@vlicmret,@vldescitem,@vldescitemrat,@qtemb,@vltotal,@ctf,@cmupi,@cue,@codbarra,@vlbasecbs
	  
	     WHILE @@FETCH_STATUS = 0
	 
		 BEGIN

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

           -- Modelo pela chave de acesso da nota (script 13, 16/11/2026); antes: serie = '1'.
           set @modelonf = dbo.FN_FIKON_MODELO_NF((select top 1 CHAVENFE from MOV_SAIDA where CODFIL = @codfil and NUMNOTA = @numnota and SERIE = @serie and NUMPEDVEN = @numpedven order by DTNOTA desc), @serie)
           if (@modelonf = '55')
		      begin 
			
			  set @modelonf = '55'
			
			  end
				else
				  begin
					 set @modelonf = '65'
			     
				  end
				  set @vlbaseibs = @vlbasecbs
				  set @vlcbs =  (@vlbasecbs * @vlaliqcbs) / 100
				  set @vlibs =  (@vlbaseibs * @vlaliqibs) / 100

INSERT INTO MOV_ITSAIDA (CODFIL,  TPNOTA,  NUMNOTA,    DTNOTA,   SERIE,   CODITPROD,  ITEM,  QTCOMP,  PRECORDZ, PRECOUNIT,  ALIQICM,   ALIQICMSUB, ALIQICMRED, VLIPI, LOCAL, TPDEPOS, PORCIPI, MINUTA,    CUBAGEM, CODASSTEC, DTASSTEC, CODEMBAL,  DPI,    DESCCOMPLE, STATUS,  NUMPEDVEN,  UNEMBAL,  CODCLI,   QTRETORN, PRECJUR, VLFRETE,    QTDEVOL,    PRECOUNITLIQ, VLSUPINF, FLINTEGRACAO, CMUP, MEDGER, HRHORA,  CODSITPROD,   RUA, BLOCO, APTO,  FILPED,   DTPROD, ALIQICMSUBUF, FILORIG,   IDADEPROD, VLBASEICMS,      VLISENTO, VLNTRIBUT, VLOUTRAS,     VLICM,    QTESTOQUE, VLBASEICMSSUB,     VLICMRET,     VLDESCITEM,     VLDESCITEMRAT,   QTSALDO, CODPROM,    QTEMB, VLBASEICMSF, VLISENTOF, VLNTRIBUTF,  VLOUTRASF,   VLICMF, VLBASEICMSSUBF, VLICMRETF, ALIQIRF, VLDESPACES, VLOUTDESP, VLOFERTA, COMPLEMENTO, CRM, VLOUTRASIPI, VLBASEIPI, VLISENTOIPI, FLBXCOMP, QTCONSIG, QTVOLUME, CODITPRODKIT, COMISSPER, COMISSVAL, FLPRODGEN, CODVENDR,     DTVALIDFIM, DTVALIDINI, VLISS,   CODNATOP, CODNATOPDIF,    CODNATOPCOMPL,   CODNATOPDIFCOMPL,       OBSFISCAL, CUEORIG, FLDETALHE, VLTOTITEM,   CTF,   CODPLANOSERV, ALIQICMSFRETE, VLFRETERAT,VLICMSFRETE, VLDESPFIN, VLICMRETFRT, VLSEGURO, VLDESPRAT, VLTOTAL,   CMUPI,  VLTOTIPI, FILPEDARMAZEM, NUMPEDARMAZEM,TIPOPEDARMAZEM, VLBASEICMSUBENT, VLICMRETENT, VLIRRF, DTALTERACAO, USERIDALT, CUE, VLTOTBASEIPI, FLLOTEVENCTO,CODPRESTSERV, DESCPRESTSERV, FLPRODPROCESS, VLJUROSVENDA, VLJUROSFIN, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV,VLBASEICMD,     VLICMD,     PRECOLISTA, ALIQPISCOFINSCSLL,VLPISCOFINSCSLL, PENCARGO, VLJUROS, VLBASEISS, ALIQISS, PRECOORIG, VLDESCNOTA, ALIQICMREPI, VLBASEICMORIGREPI, VLICMORIGREPI,VLICMREPI, ALIQPISSUB, ALIQCOFSUB, VLPISSUB, VLCOFSUB, FLSUBSTINTERNA, QTVENDAKIT, PCONTSOC, VLPPIS, VLPCONTSOC,PPIS, ALIQICMDIF, VLBASEICMDIF, VLICMDIF, VLICMDESCONTOF, VLTAC, CODTECNICO, VLPISDESCONTOF, VLCOFDESCONTOF, ALIQICMDIFSAI, VLBASEICMSDIFSAI, VLICMDIFSAI, NUMORC, CUSTOGER, ALIQICMSATIVO, VLBASEICMSATIVO, VLICMSATIVO, FLATUTRAN, FLPREINDIG, VLPISRET, VLCSLLRET, VLIRRET, VLCOFINSRET, ALIQPCTM, ALIQICMREDUF, VLNTRIBUTD, DESCUNIDTRIBUTAVELNF, FATORCONVTRIBUTAVELNF, VLICMRETV, ALIQICMCREDITO,  VLICMCREDITO, ORIGEMPROD, DESCLICITACAO, ALIQIBPT, VLIBPT, VERSAOIBPT, NUMFCI, CONVERSAO, VLCUSTOIMP, OBSCOMPLPROD, FLESCFISCALDIF, CFOPNOTA, CTFNOTA, CODJUST, CHAVEIBPT, FONTEIBPT, ALIQIBPTEST, VLIBPTEST, ALIQIBPTMUN, VLIBPTMUN,VLICMSRECUPTRANSF, ALIQICMUF, VLICMSSTRECUPTRANSF,  ALIQFECEP , ALIQICMPART, VLFECEPF, VLFECEP,  VLFECEPSTF, VLFECEPST, VLICMPARTUFF, VLICMPARTUF, VLICMPARTF, VLICMPART, FLFECEPADIC, CEST, VLBASEPIS, VLBASECOFINS, CUETRANSF, CMUPTRANSF,CSTIPI, CSTPIS, CSTCOFINS, CODBARRA, VLBASEFECEPF, VLBASEFECEPSTF, ALIQFECEPST, VLBASEICMPARTUFF,  CODIGO53, VLAJUSTEITEM, CODIGO52, CODIGO56, VLBASESTRETANT, VLICMSTRETANT, VLREMGST, VLBASEFCPSTRETANT, ALIQFCPSTRETANT, VLFCPSTRETANT,VLBASEICMSEFETIVO,     VLICMSEFETIVO,  VLICMSGARANTIDO, VLBASEICMSGARANTIDO, VLICMEG, VLBASEICMEG, VLSUBSTITUTOSTRETANT,  VLICMOPERACAO, ALIQICMDIFERIMENTO, VLICMDIFERIDO, VLICMSDESON, CODMOTDESICMS,VLFECEPSTGARANTIDO, VLBASEDESONDIFERF, VLBASEICMUE, VLICMUE, VLBASEICMSSTUE, VLICMSSTUE, VLFECEPSTUE, VLBASEICMMUP, VLICMMUP, VLBASEICMSSTMUP, VLICMSSTMUP, VLFECEPSTMUP, VLICMOPERSTF,      VLFECEPOPERSTF, VLFECEPUE, VLFECEPMUP, VLNTRIBUTUF, VLDESCBASEPIS, VLDESCBASECOFINS, CUSTORE, CUE_RE6763, CMUP_RE6763, VLCASHBACKPROFISCONSTRU, CODITPRODBENEF, CLASTRIBCBS, CLASTRIBIBS, CLASTRIBIS, CSTCBS, CSTIBS, CSTIS,  VLBASECBS,     ALIQCBS,    VLCBS, VLBASEIBS,          ALIQIBS,          VLIBS,  VLBASEIBSMUN,            ALIQIBSMUN, VLIBSMUN, VLBASEIS, ALIQIS, VLIS, PERCREDUTOR  ) 
VALUES (                 @codfil, @tpnota, @numnota, @dtnota,    @serie, @coditprod,  @item, @qtcomp,   NULL,  @precounit,  @aliqicm,  @ALIQICMSUB,        0,         0,    1,     'L',       0,     NULL,  @cubagem,       NULL,     NULL,     0,      @dpi,       NULL,     2,     @numpedven, @UNEMBAL, @codcli,    NULL,      0,      @vlfrete,     0,         @precounit,   0,         NULL,    @cmup,    0,   @hrhora, @codsitprod,  NULL, 0,    NULL,   @codfil,   NULL,     20,        @codfil,     NULL,   @vlbaseicm,           0,        0,    @vloutras,    @vlicm,   @QTESTOQUE,   @vlbaseicmssub,    @vlicmret,  @vldescitem,   @vldescitemrat,      0,       0,     @qtemb,       0,            0,        0,     @VLOUTRASF,     0,          0,            0,       0,         0,          0,       0,          NULL,     0,       0,           0,         0,       NULL,      0,        0,          NULL,        NULL,      NULL,      NULL,    @CODVENDR,      NULL,       NULL,       0,    @codnatop,      NULL,   @codnatopdifcompl, NULL,                 @obsfiscal,    NULL,    NULL,    @vltotal,   @ctf,    NULL,               0,           0,         0,           0,      NULL,         0,        0,       @vltotal, @cmupi,    0,         NULL,         NULL,           NULL,            NULL,          NULL,       0,       NULL,      NULL,  @cue,      0,            'N',          0,           NULL,           'N',           NULL,         0,             0,              0,           @vlbaseicmd,   @vlicmd,     0,             0,                0,             0,        0,        0,        0,   @precounit,    0,             0,             0,              0,         0,           0,           0,        0,          0,         NULL,          0,        0,       0,        0,       0,      0,          0,             0,         0,         0,        0,             0,            0,                0,             0,               0,       0,      NULL,        0,              0,             0,          NULL,       'N',       0,        0,         0,        0,          0,        0,            0,                NULL,                 NULL,            0,             0,              0,          0,           NULL,        NULL,  NULL,     NULL,      NULL,    1,        NULL,           NULL,         NULL,         0,      NULL,    NULL,    NULL,      NULL,       NULL,         NULL,      NULL,        NULL,      NULL,         @aliqicm,        NULL,                0,          0,         0,          0,        0,         0,          0,             0,         0,           0,         'N',     NULL,      0,         0,        NULL,       NULL,     NULL,  NULL,    NULL,   @CODBARRA,      0,            0,              0,            0,              NULL,      NULL,        NULL,    NULL,          0,           0,             0,             0,                0,               0,       @vlbaseicmsefetivo, @vlicmsefetivo,      NULL,                NULL,          NULL,     NULL,                0,              NULL,            NULL,               NULL,         NULL,       NULL,             NULL,           NULL,               0,        0,            0,            0,          0,          0,           0,           0,             0,           0,      @vlicmsefetivo,          0,             0,           0,           0,          0,                0,          0,          0,          0,                  0,                   0,        '000001',   '000001',       NULL,   '000', '000',   NULL, @vlbasecbs,   @vlaliqcbs,  @vlcbs,     @vlbaseibs,      @vlaliqibs,      @vlibs,       @vlbaseibsmun,          0,         0,         0,      0,     0,        0)
  

UPDATE MOV_ITPED  WITH (READCOMMITTED) SET   DTNOTA =  @dtnota, QTEMITIDO =  @qtcomp, STATUS =  6, NUMNOTA =  @numnota, TPNOTA =  @tpnota, QTFAT =  QTFAT + @qtcomp, QTLIB =  QTLIB - @qtcomp, QTCORTE =  case when qtcorte> 0 then QTCORTE - @qtcomp else 0 end  WHERE 1=1 AND MOV_ITPED.CODFIL = @codfil AND MOV_ITPED.NUMPEDVEN = @numpedven AND MOV_ITPED.TIPOPED = 0 AND MOV_ITPED.CODITPROD = @coditprod AND MOV_ITPED.ITEM = @item

set @qtd_itens_s32 = @qtd_itens_s32 + 1   -- script 32

exec SPU_PROLOCI 1, @codfil, 'L', @coditprod, @qtcompbaixa, @qtcompbaixa, 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0 

INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,    FISICO,  RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO,    FISICOPOS,         RESFISPOS,       ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG,  DTPROC,           ROTINA,                  COMANDOSQL,                                                                                                                                                                                   IDENTPROC ) 
VALUES ( @codfil, @numpedven,@numnota, GETDATE(),@tpnota,                   'S',     3,    @coditprod, @fisico,  @resfis,     0,         0,      0,       0,      0,         0,           0,       -@qtcomp,      'FISICO;RESFIS;', 'N',   @fisico-@qtcomp,  @resfis-@qtcomp ,         0,           0,         0,        0,           0,              0,             0,         @codfil, getdate(), 'GRAVAITENSNOTAFISCAL', '{CALL SPU_PROLOCI(1, '+convert(varchar,@codfil)+', L, '+convert(varchar,@coditprod)+', -'+convert(varchar,@qtcomp)+', -'+convert(varchar,@qtcomp)+', 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0)} ',                                    'INTEGRADOR FIKON' )


  set @totalPeso= @totalPeso +  (Select sum(PESOLIQ*QTCOMP) from mov_itped  where numpedven=@numpedven and CODFIL = @codfil and TIPOPED = 0 AND CODITPROD=@CODITPROD AND ITEM = @item)   -- script 32: peso do item (antes todos os 'R' do produto)


     FETCH NEXT FROM CR_INSERE_ITENS INTO  @codvendr, @tpnota,@coditprod, @item, @qtcomp,@precounit,@aliqicm, @ALIQICMSUB,@cubagem,@dpi,@UNEMBAL,@vlfrete,@cmup,@codsitprod,
	  @vlbaseicm,@vlicm, @vlbaseicmssub,@vlicmret,@vldescitem,@vldescitemrat,@qtemb,@vltotal,@ctf,@cmupi,@cue,@codbarra,@vlbasecbs
	       


  END

  CLOSE CR_INSERE_ITENS
  DEALLOCATE CR_INSERE_ITENS 

 -- script 32: nota sem nenhum item faturavel nao fica gravada vazia
 if @qtd_itens_s32 = 0
 begin
    declare @msg_s32 varchar(300) = 'Pedido ' + convert(varchar(12), @numpedven) + ' sem itens faturaveis na filial ' + convert(varchar(5), @codfil)
                                  + ' (STATUS 5, FLLIBFAT S, TPPED R/P, FILORIG = filial): nota ' + convert(varchar(12), @numnota) + ' serie ' + @serie + ' nao gravada.';
    THROW 50001, @msg_s32, 1;
 end

 -- script 32: total pelos itens faturados nesta nota (antes todos os 'R' do pedido)
 set @totalPedido =  (Select sum(VLTOTITEM+VLFRETE-VLDESCITEMRAT) from mov_itped  where numpedven=@numpedven and CODFIL = @codfil and TIPOPED = 0
                        and NUMNOTA = @numnota and DTNOTA = @dtnota and STATUS = 6 and FILORIG = @filorig)


 UPDATE MOV_SAIDA SET VLtotal= @totalPedido, PESO = @totalPeso, PESOLIQ = @totalPeso where numnota=@numnota and numpedven=@numpedven and serie=@serie

 -- script 32: parcial enquanto restar item nao faturado e nao cancelado (antes: existe item com TPPED <> 'R')
 if(select count(*) from  mov_itped where numpedven=@numpedven and CODFIL = @codfil and TIPOPED = 0 and ISNULL(STATUS, 0) NOT IN (6, 9)) > 0
    begin

	update MOV_PEDIDO set STATUS=8 where NUMPEDVEN=@numpedven
	update dbgemco..fikon_integracao_pedido  set status='FATURADO PARCIAL' where pedido_gemco = @numpedven 

	end
	   else
	     begin

		 update MOV_PEDIDO set STATUS=6 where NUMPEDVEN=@numpedven
		 update dbgemco..fikon_integracao_pedido  set status='FATURADO' where pedido_gemco = @numpedven 

		 end


		 -- TPPED = 'P' só para NF-e (script 13, 16/11/2026); antes: serie = '1'.
		 if(dbo.FN_FIKON_MODELO_NF((select top 1 CHAVENFE from MOV_SAIDA where CODFIL = @codfil and NUMNOTA = @numnota and SERIE = @serie and NUMPEDVEN = @numpedven order by DTNOTA desc), @serie) = '55')
		    begin
			  
			   update mov_itped set tpped='P' where numpedven=@numpedven and TPPED='R'

            end

		


  
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

SELECT o.name, o.modify_date,
       CASE WHEN o.name = 'SP_FIKON_INTEGRA_MOV_ITSAIDA'
            THEN CASE WHEN CHARINDEX('script 32', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script32
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_INTEGRA_MOV_ITSAIDA', 'SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT32')
 ORDER BY o.name;
GO
