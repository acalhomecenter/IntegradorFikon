/*
  18 - Devolução FIKON -> Gemco: validações e correções das procedures de devolução - DEV  -  16/11/2026
  Base: DEV (DB-TREINO 10.1.5.226), banco dbgemco.
  Na outra base use o 18_..._PRODUCAO.sql (a ENT_ITENT do DEV tem a coluna PERCREDUTOR, a da produção não).

  O que aconteceu (devolução 27, filial 502, pedido FIKON 2013678, produto 722575):
    A ApiAcal mandou como nota de saída a NFC-e 117, que está CANCELADA (a venda ativa é a NFC-e 120).
    SP_FIKON_INTEGRA_DEVOLUCAO só gravava se o STATUS da saída fosse < 8; com a 117 (STATUS 9) fez só um PRINT
    e não gravou o cabeçalho. SP_FIKON_INTEGRA_ITEM_DEVOLUCAO tentou gravar o item sem cabeçalho -> erro de FK
    (ENT_ITENT_FK_NOTA), rollback, e a FIKON recebeu "não retornou um resultado válido". Nada ficou gravado.
    A ApiAcal foi corrigida para usar a nota de saída ATIVA; este script corrige as procedures.

  O que muda:
    SP_FIKON_INTEGRA_DEVOLUCAO (procedure completa abaixo):
      1. Para com erro claro (RAISERROR) quando: estabelecimento sem filial; devolução já integrada (mesma chave);
         nota de saída não encontrada; nota de saída cancelada; nota de saída já totalmente devolvida.
         Antes eram um PRINT ou nada.
      2. Série da NF-e de devolução pela chave de acesso (posições 23-25). Antes '1' fixo.
    SP_FIKON_INTEGRA_ITEM_DEVOLUCAO (procedure completa abaixo):
      3. Mesmas validações da nota de saída + cabeçalho da devolução gravado + produto na venda + saldo a devolver.
      4. Reparte a quantidade pelos itens da venda com saldo (antes cada linha do produto recebia a quantidade toda).
      5. ENT_ITENT com preço unitário, embalagem (QTEMB -> CONVERSAO), CODEMBAL e TOTESTOQUE do item vendido,
         série e data do cabeçalho. Antes @precounit/@conversao/@totestoque ficavam nulos.
      6. Extrato (MOV_EXTRATOPROD): quantidade, filial e data reais (antes 1, CODFILLOG 8 e '08/18/2026' fixos)
         e reserva sem mudança (antes somava a quantidade na reserva).
      7. MOV_ITSAIDA: STATUS 8 quando o item fica todo devolvido e 7 quando parcial (antes dava 7 na devolução total);
         segunda devolução parcial do mesmo item passa a somar QTDEVOL (antes só gravava se QTDEVOL = 0).
    SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO: não muda.

  Como rodar: no SSMS, conectado na DEV, banco dbgemco, executar o script INTEIRO (F5).
    - O 1º bloco confere a versão das procedures e guarda cópias <nome>_BKP_SCRIPT18. Se algo estiver
      diferente, o script para (SET NOEXEC ON) e nada é alterado.
  Para voltar atrás: abrir a <nome>_BKP_SCRIPT18, trocar o nome pelo original e executar como ALTER.
  Depois: publicar a ApiAcal corrigida e reenviar da FIKON o evento DEVOLUCAO 27.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @erro varchar(1000) = '';
DECLARE @def nvarchar(max);

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_DEVOLUCAO'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_INTEGRA_DEVOLUCAO nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0xE842354C7D16F0CE7F40534BDC04B230F82B228BEA3D2B9392E848B341EE2242 AND CHARINDEX(N'script 18', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_DEVOLUCAO esta numa versao diferente da esperada. ';

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_ITEM_DEVOLUCAO'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_INTEGRA_ITEM_DEVOLUCAO nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0x3DEF77C6DF4D6E4C385F0D0A19CB8C556D03421DD1A4628C2BD9BD673650E257 AND CHARINDEX(N'script 18', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_ITEM_DEVOLUCAO esta numa versao diferente da esperada. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_DEVOLUCAO_BKP_SCRIPT18') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_DEVOLUCAO')), N'SP_FIKON_INTEGRA_DEVOLUCAO', N'SP_FIKON_INTEGRA_DEVOLUCAO_BKP_SCRIPT18');
        EXEC sys.sp_executesql @def;
    END
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_ITEM_DEVOLUCAO_BKP_SCRIPT18') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_ITEM_DEVOLUCAO')), N'SP_FIKON_INTEGRA_ITEM_DEVOLUCAO', N'SP_FIKON_INTEGRA_ITEM_DEVOLUCAO_BKP_SCRIPT18');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_DEVOLUCAO_BKP_SCRIPT18') IS NULL
       OR OBJECT_ID('dbo.SP_FIKON_INTEGRA_ITEM_DEVOLUCAO_BKP_SCRIPT18') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar as copias de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copias guardadas: <nome>_BKP_SCRIPT18.';
END
GO

/* ===================== 2. SP_FIKON_INTEGRA_DEVOLUCAO (completa) ===================== */
ALTER PROC [dbo].[SP_FIKON_INTEGRA_DEVOLUCAO]  
@chavenfesaida varchar(44),
@chavenfe varchar(44),
@estabelecimento numeric(15,0),
@numnota numeric(12)

as

-- script 18 (16/11/2026): valida a nota de saida antes de gravar. Antes, nota de saida cancelada ou
-- nao encontrada so fazia PRINT, nada era gravado e o item quebrava na FK da ENT_ITENT sem explicacao
-- (devolucao 27 da filial 502 apontando para a NFC-e 117 cancelada). Serie da nota pela chave.

    declare @codfil int
	declare @tpnota varchar(3) = '26'
	declare @codcli numeric(12)
	declare @data date = getdate()
	declare @estado varchar(2)
	declare @vltotal numeric(15,2) = 0 
	declare @codfilsai int
	declare @numnotasai numeric(12)
	declare @filpedsai int
	declare @CONDPGTOSAI varchar(3)
	declare @seriesai varchar(3)
	declare @obsfiscal varchar(200) = 'NF: 374818 SERIE: 1 DT: 27/05/2026 VALOR: 289,89'
	declare @dtnotasai date 
	declare @tpnotasai varchar(3)
	declare @codvendr int
	declare @VLBASECBS numeric(15,2)
	declare @VLCBS numeric(15)
	declare @VLBASEIBS numeric(15)
	declare @vlibs numeric(15)  
	declare @VLBASEIBSMUN numeric(15)
	declare @VLIBSMUN numeric(15)
	declare @serie varchar(3)
	declare @DATAHORAUTC varchar(50) = FORMAT(SYSDATETIMEOFFSET(), 'yyyy-MM-ddTHH:mm:sszzz')
	


declare @statussai int
declare @msg varchar(400)

set @codfil = (select filial_genco from [FIKON_VINCULO_FILIAL] where  filial_fikon = @estabelecimento)
if @codfil is null
begin
   set @msg = 'Estabelecimento FIKON ' + convert(varchar(15), @estabelecimento) + ' sem filial no Gemco (FIKON_VINCULO_FILIAL).'
   raiserror(@msg, 16, 1)
   return
end

if exists (select 1 from ENT_NOTA where TPNOTA = @tpnota and CHAVENFE = @chavenfe)
begin
   set @msg = 'Nota de devolucao ' + convert(varchar(12), @numnota) + ' (chave ' + isnull(@chavenfe, '') + ') ja esta integrada no Gemco.'
   raiserror(@msg, 16, 1)
   return
end

-- nota de saida pela chave; se houver mais de uma linha com a chave, a nao cancelada primeiro
select top 1 @statussai = isnull(STATUS, 0), @numnotasai = NUMNOTA, @seriesai = SERIE
  from MOV_SAIDA
 where CHAVENFE = @chavenfesaida
 order by case when STATUS = 9 then 1 else 0 end

if @statussai is null
begin
   set @msg = 'Nota de saida (chave ' + isnull(@chavenfesaida, '') + ') nao encontrada no Gemco.'
   raiserror(@msg, 16, 1)
   return
end

if @statussai = 9
begin
   set @msg = 'Nota de saida ' + convert(varchar(12), @numnotasai) + ' serie ' + isnull(@seriesai, '') + ' esta cancelada no Gemco; a devolucao precisa apontar para a nota de saida ativa.'
   raiserror(@msg, 16, 1)
   return
end

-- serie da NF-e de devolucao: posicoes 23-25 da chave (antes '1' fixo)
set @serie = case when len(@chavenfe) = 44 and @chavenfe not like '%[^0-9]%'
                  then convert(varchar(3), convert(int, substring(@chavenfe, 23, 3)))
                  else '1' end

if @statussai < 8

begin

   set @codfil = (select filial_genco from [FIKON_VINCULO_FILIAL] where  filial_fikon = @estabelecimento)

   select top 1 @estado = estado, @filpedsai = FILPED, @CONDPGTOSAI =  CONDPGTO ,  @codvendr = codvendr,  @codcli = codcli, @codfilsai = codfil, @numnotasai = NUMNOTA, @dtnotasai = dtnota, @tpnotasai = tpnota, @numnotasai = NUMNOTA, @seriesai=serie from mov_saida where CHAVENFE = @chavenfesaida order by case when STATUS = 9 then 1 else 0 end

   UPDATE MOV_SAIDA  WITH (READCOMMITTED) SET   CODDEVOL =  '33'  WHERE 1=1 AND CODFIL =  @codfilsai AND TPNOTA = @tpnotasai AND NUMNOTA =  @numnotasai AND SERIE =  @seriesai AND DTNOTA =  @dtnotasai


	INSERT  INTO ENT_NOTA( CODFIL, TPNOTA, CODREMET, SERIE, NUMNOTA, DTEMISSAO, DTNOTA, DTPEDIDO, DTCANCEL, DTENTREGA,               ESTADO,   GUIA,   ALIQICM, CODNATOP,   CODTRANSP,   NFCONHEC,  CODMENSAG, PESO, SITUACAO, FLEMISSAO, VLDESPACES, VLACRESCIM, VLBASEICMS, VLDESCONTO, VLDESPFIN, VLDESPICM, VLFRETE, VLICM, VLICMRET, VLIPI, VLMERCAD,   VLOUTDESP,  VLSEGURO, STATUS, PDESC1, PDESC2, PDESC3, PDESC4, PDESC5, PDESC6,    CODFILSAI,       NUMNOTASAI,    VLISENTO,    VLOUTRAS,   FILPEDSAI,    CONDPGTOSAI,      DATCOT,  LOTCOT,  NUMLAN,  VLBASEIPI,     SERIESAI,    PLACAVEIC, ORDEMCHEG, VLBASEICMSSUB, VLTOTAL,  PDESCDUP, VLDESCDUP,  DTATUEST,       FLATUEST, ENDENT, OBS, CODFILSIMPFAT, TPNOTASIMPFAT, NUMNOTASIMPFAT, SERIESIMPFAT, CODREMETSIMPFAT, CODSITTITCPG, CODUSER, CODFUNCCONF, CODFUNCDESC, HRFIMDESC, HRINIDESC, VLDESCARGA, VLISENTOIPI, VLOUTRASIPI, NUMDOCTO, PDESCICMS, VLIMPIMPORT, FLFISCAL, OBSFISCAL,       FLINTEGRACPG, FLREPLICA,   DTNOTASAI,      TPNOTASAI,   CONTROLE, PDESCESP, PFATURA, CODDEVOL, DESCREMETENTE, CODNATOPCOMPL, CODNATOPDIF, CODNATOPDIFCOMPL, FLCIFFOB,      NUMPORTARIA, VLIRRF, CODCONTACOB, CODTPCOB, NUMAGECOB, NUMAGEDEST, NUMBCOCOB, NUMBCODEST, NUMCTACOB, NUMCTADEST, VLISS, VLBASEISS, VLBASEIRRF, ALIQISS, ALIQIRRF, SERIECONTRAFIN, TPCONTRATO, NUMCONTRAFIN, CODEMPR, TPNEG, CODRETIMPRENDA, DIGAGECOB, DIGAGEDEST, DIGCONTACOB, DIGCONTADEST, ANOPORTARIA, CODDOCA, PLACACARRETA, NUMPF, VLFUNRURAL,          IDENTPROC,                       DTALTERACAO, USERIDALT, FLTPNFDEVOL, PESOLIQ, PDESCFIN, CODVENDR,    ALIQINSS, VLBASEINSS, VLINSS, FLENDERENTRADA, NRDIASATRASO, VLSUFRAMA, FLCONTRANF, NUMCONTRANF, VLBASEICMSSUBC, VLICMRETC, QTRECDEVIMP, VLICMSANTEC, NUMCTRLPART, PERCDESCPRESUMIDOF, PERCDESCPRESUMIDOV, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, NUMDAR, VLICMSGARANTIDO, VLBASEICMD, VLICMD, FLSEMSERIE, VLCOFSUB, VLPISSUB, VLCDO, CODAUTORIZACAO, ALIQCSLL, VLCSLL, VLBASECSLL, ALIQCOFINSRET, ALIQPISRET, VLBASECOFINSRET, VLBASEPISRET, VLCOFINSRET, VLPISRET, FLSSCC, VLJUROSFIN, VLJUROS, FLINTCONF, VLICMORIGREPI, VLBASEICMORIGREPI, VLICMREPI, VLICMSGARANTIDODAR, DTREFERDAR, DTVENCDAR, TPPGTO, VLBASEICMDIF, VLICMDIF, CODFILORIG, CODREMETORIG, NUMNOTAORIG, SERIEORIG, CODCLASCONSENERELE, CODUNICONENERELE, DEMANDAENERELEFORA, DEMANDAENERELEPONTA, DTFIMCONENERELE, DTINICONENERELE, NUMCONSUMIDORESENERELE, KWH, VLICMDESCONTO, VLDESCNOTA, VLICMTRANSF, ANOMESAPU, VLBASEICMEG, VLICMEG, FLGERARF, VLPISDESCONTO, VLCOFDESCONTO, VLICMCREDITO, VLPIN,    MODELONF, DTPREVRETMDT, OBSNFE, VLICMCONHECSUB, VLBASEICMSGARANTIDO, VLBASEICMDIFANTEC, VLICMDIFANTEC, NUMORCDESP, TPVERBA, VLPINDAR,                                                                                                            DTAUTORIZACAONFE,        NUMNFE, DIGNFE, STATUSNFE, DTCANCELAMENTONFE, STATUSANT, CODFORNECOLIGADO, ICMPRESUMIDO, CODFILCOMPLORIG, CODREMETCOMPLORIG, TPNOTACOMPLORIG, NFCOMPLORIGINAL, SERIECOMPLORIG, NSU, DTIMPRESSAO, FLSEGURO, FLCONTINGENCIA, FLNFE, VERSAONFE, VLBASEICMSANTEC,  FLDTVENCTOCPGCONFNF, VLNTRIBUTD, VLICMRETV, FLUTILNOTA, DATAHORAUTC, VLICMRETSIMPFAT, SEQINVDATA, VLFECEP, VLFECEPST, VLICMPARTUF, VLICMPART, CODCONTR, FLCONFPORTARIA, DTCONFPORTARIA, NRSERIEECFREF, NUMNOTAREF, DTNOTAREF, SERIEREF, MODELONFREF, CODFILREF, DTSIMPFAT, NUMNOTANFSE, CODVERIFICACAONFSE, VLICMSDESON, VLFECEPSTGARANTIDO, CODMUNIBGEORIG, ESTTRAJETOORIG, CIDTRAJETOORIG, CODMUNIBGEDEST, ESTTRAJETODEST, CIDTRAJETODEST, QTVOLUME, FLEXCICMSBCPISCOFINS, FLEXCFCPBCPISCOFINS, FLCROSSDOCKINGAUT, FLCONTRIBUINTECPRB, TPSERVICOREINF, OBSREINF, CNPJINTERMEDIADOR, IDENTINTERMEDIADOR, FLMOVENDERECAR, CODFINDOCE, CODTIPFAT,   VLBASECBS,        VLCBS,    VLBASEIBS,      VLIBS,    VLBASEIBSMUN,    VLIBSMUN, VLBASEIS, VLIS , chavenfe) 
				VALUES ( @codfil, @tpnota, @codcli, @serie, @numnota,     @data   ,  @data,    NULL,   NULL,      @data,                 @estado,   NULL,     0,      null,        NULL,       NULL,      NULL,     0,    NULL,       NULL,       0,           0,         0,          0,           0,       NULL,     0,      0,       0,       0,    @vltotal,      0,          0,      1,     0,       0,       0,     0,     NULL,   NULL,    @codfilsai,       @numnotasai,       0,       @vltotal,   @filpedsai,   @CONDPGTOSAI,      NULL,    NULL,    NULL,       0,        @seriesai,     NULL,     NULL,          0,         @vltotal,    0,        0,       GETDATE() ,        'S',     0,    NULL,     NULL,        NULL,             NULL,         NULL,            NULL,           NULL,     537,      NULL,         NULL,       NULL,       NULL,      NULL,          0,        0,          NULL,      0,          0,        NULL,     @obsfiscal,         NULL,        NULL,     @dtnotasai,     @tpnotasai,    NULL,       0,      NULL,    NULL,         NULL,         0,             141,              1,           NULL,         NULL,     NULL,      NULL,       NULL,      NULL,      NULL,     NULL,       NULL,       NULL,       NULL,    NULL,     NULL,      NULL,     NULL,      NULL,      NULL,          NULL,         NULL,       1,     0,        NULL,          NULL,     NULL,        NULL,         NULL,         NULL,      NULL,     NULL,      NULL,     0,  'DEVOLUCAO REALIZADA VIA INTEGRADOR FIKON', NULL,           NULL,     'O',          0,       NULL,   @codvendr,        NULL,      NULL,    NULL,       NULL,           NULL,       NULL,      NULL,       NULL,          NULL,         NULL,      NULL,       NULL,        NULL,            NULL,               NULL,              NULL,               NULL,     NULL,          NULL,           0,       0,      NULL,       NULL,     NULL,    NULL,       NULL,        NULL,    NULL,     NULL,        NULL,         NULL,           NULL,         NULL,         NULL,      NULL,     'N',      NULL,     NULL,    'N',         NULL,            NULL,           NULL,        NULL,              NULL,      NULL,     2,        NULL,       NULL,      NULL,          NULL,        NULL,        NULL,          NULL,               NULL,              NULL,              NULL,             NULL,              NULL,              NULL,           NULL,     NULL,      NULL,        0,             0,      NULL,       NULL,    NULL,       NULL,            NULL,        NULL,       NULL,  '55',        NULL,      NULL,        NULL,               NULL,              NULL,            NULL,       NULL,        NULL, NULL,                                                                                                                    NULL,                 0,      0,      NULL,      NULL,                NULL,       0,                 NULL,         NULL,            NULL,                NULL,           NULL,           NULL,    NULL,     NULL,      NULL,        NULL,      NULL,     NULL,        NULL,               NULL,             NULL,     NULL,       NULL,   @DATAHORAUTC,       0,            NULL,       0,         0,        0,          0,       NULL,        NULL,            NULL,         NULL,           NULL,     NULL,   NULL,       NULL,       NULL,        NULL,      NULL,            NULL,            NULL,            NULL,             NULL,          NULL,           NULL,            NULL,           NULL,          NULL,        NULL,          NULL,                 NULL,               NULL,              NULL,            NULL,           0,           NULL,               NULL,               NULL,      NULL,       null,       @VLBASECBS,       @VLCBS,   @VLBASEIBS,     @vlibs,  @VLBASEIBSMUN,   @VLIBSMUN,         0,    0, @chavenfe)


	--SELECT SUM(FISICO + TECNICO + MOSTRUARIO) ESTQTOTAL FROM CAD_ITPROD ITP, CAD_PRODLOC LOC, CAD_FILIAL CF  WHERE 1=1 AND ITP.CODITPROD = LOC.CODITPROD AND LOC.CODFIL = CF.CODFIL AND ITP.CODPROD = 49944 AND CF.CODFILCUST = 8


	--SELECT CAD_PRODLOC.FISICO , CAD_PRODLOC.MOSTRUARIO , CAD_PRODLOC.TECNICO  FROM CAD_PRODLOC   WHERE 1=1 AND  CODFIL =  1 AND  TPDEPOS =  'L' AND  CODITPROD =  66333

	--SELECT FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, MOSTRUARIO, TECNICO, TRANSITO, CONSIGNACAO, ECOMMERCE, REVERSA, ENDERECAR  FROM CAD_PRODLOC  WHERE 1=1 AND CODFIL = 1 AND TPDEPOS =  'L' AND CODITPROD =  66333


	INSERT  INTO ENT_NOTASAI(CODFIL,  TPNOTA,  CODREMET,  SERIE, NUMNOTA,   CODFILSAI,  TPNOTASAI,  NUMNOTASAI,    SERIESAI,   DTNOTASAI,   VLMERCAD,  CODVENDR, CONDPGTOSAI, FILPEDSAI,    VLTOTAL,    VLJUROSFIN, FLINTEGRACPG, FLSEGURO,  DTNOTA) 
	VALUES   (               @codfil, @tpnota,  @codcli,    @serie, @numnota,  @codfilsai, @tpnotasai,  @numnotasai,  @seriesai,  @dtnotasai,  @vltotal,  @codvendr , @CONDPGTOSAI, @filpedsai, @vltotal,        0,        'N',        'N'   ,  @data  )


	declare @status int 

	--declare @tpdep varchar(1) 
	--declare @fisico numeric(12,2)
	--declare @resfis numeric(12,2)
	
	--declare @local int

	--declare @coditprod varchar(9)
	--declare @qtcomp numeric(12,2)
	--declare @codprod numeric(9)
	--declare @item int
	--declare @precounit numeric(15,2)
	--declare @vltotItem numeric(15,2)
	--declare @conversao numeric(15,2)

	--declare @totestoque numeric(15,2)

	--declare @cmup numeric(15,4)
	--declare @cue numeric(15,4)

	--declare @seqjornal numeric(12)


	if(SELECT sum(QTCOMP) - sum(QTDEVOL) FROM MOV_ITSAIDA  WHERE 1=1 AND CODFIL = @codfilsai AND TPNOTA = @tpnotasai AND NUMNOTA = @numnotasai AND SERIE = @seriesai AND DTNOTA = @dtnotasai)>0
			
	 set @status = 7

	else
   
	 set @status = 8


	UPDATE MOV_SAIDA  WITH (READCOMMITTED) SET   STATUS =  @status  WHERE 1=1 AND CODFIL =  @codfilsai AND TPNOTA =  @tpnotasai AND NUMNOTA =  @numnotasai AND SERIE =  @seriesai AND DTNOTA =  @dtnotasai


								

end
  else
  RAISERROR('Nota fiscal de saida ja esta totalmente devolvida no Gemco.', 16, 1)
GO

/* ===================== 3. SP_FIKON_INTEGRA_ITEM_DEVOLUCAO (completa) ===================== */
ALTER PROC [dbo].[SP_FIKON_INTEGRA_ITEM_DEVOLUCAO] 
@chavenfesaida varchar(44),
@coditprod numeric(12,0),
@estabelecimento numeric(15,0),
@numnota numeric(12),
@qtcomp numeric(12,4)

          
as

-- script 18 (16/11/2026): valida a nota de saida, o cabecalho da devolucao e o saldo do produto;
-- reparte a quantidade pelos itens da venda com saldo; preco, embalagem e total do item vendido;
-- serie/data do cabecalho; extrato com quantidade, filial e data reais; status 8 quando o item fica
-- todo devolvido (antes 7) e devolucao parcial repetida passa a somar (antes so gravava se QTDEVOL = 0).

declare @status int 
declare @tpnota varchar(3) = 26
declare @data date = getdate()
declare @tpdep varchar(1) 
declare @fisico numeric(15,4)
declare @resfis numeric(15,4)
declare @local int
declare @codprod numeric(9)
declare @item int
declare @precounit numeric(15,4)
declare @vltotItem numeric(15,2)
declare @conversao numeric(15,4)
declare @totestoque numeric(15,2)
declare @cmup numeric(15,4)
declare @cue numeric(15,4)
declare @seqjornal numeric(12)
declare @codvendr int
declare @filpedsai int
declare @codcli numeric(12,0)
declare @codfilsai int
declare @numnotasai numeric(12,0)
declare @dtnotasai date
declare @tpnotasai varchar(3)
declare @seriesai varchar(3)
declare @codfil int
declare @serie varchar(3)        -- script 18: serie e data do cabecalho ENT_NOTA da devolucao
declare @dtnota date
declare @statussai int
declare @codembal numeric(4,0)
declare @qtsaldo numeric(15,4)   -- saldo a devolver do item da venda
declare @qtitem numeric(15,4)    -- quantidade devolvida neste item da venda
declare @restante numeric(15,4)
declare @msg varchar(400)

        select  top 1 @statussai = isnull(STATUS, 0), @filpedsai = FILPED,  @codvendr = codvendr,  @codcli = codcli, @codfilsai = codfil, @numnotasai = NUMNOTA, @dtnotasai = dtnota, @tpnotasai = tpnota, @numnotasai = NUMNOTA, @seriesai=serie from mov_saida where CHAVENFE = @chavenfesaida order by case when STATUS = 9 then 1 else 0 end

		set @coditprod = LEFT(@coditprod, LEN(@coditprod) - 1) 

		set @codfil = (select filial_genco from [FIKON_VINCULO_FILIAL] where  filial_fikon = @estabelecimento)

		if(@codfil in (5,8))
		  begin
		    set @tpdep = 'D'
			set @local = 2
		  end
		    else
			  begin
			     set @tpdep = 'L'
			     set @local = 1
			  end

		-- script 18: validacoes
		if @statussai is null
		begin
		   set @msg = 'Nota de saida (chave ' + isnull(@chavenfesaida, '') + ') nao encontrada no Gemco.'
		   raiserror(@msg, 16, 1)
		   return
		end
		if @statussai = 9
		begin
		   set @msg = 'Nota de saida ' + convert(varchar(12), @numnotasai) + ' serie ' + isnull(@seriesai, '') + ' esta cancelada no Gemco.'
		   raiserror(@msg, 16, 1)
		   return
		end

		select top 1 @serie = SERIE, @dtnota = DTNOTA
		  from ENT_NOTA
		 where CODFIL = @codfil and TPNOTA = @tpnota and NUMNOTA = @numnota and CODREMET = @codcli
		   and CODFILSAI = @codfilsai and TPNOTASAI = @tpnotasai and NUMNOTASAI = @numnotasai
		   and SERIESAI = @seriesai and DTNOTASAI = @dtnotasai
		 order by DTNOTA desc
		if @serie is null
		begin
		   set @msg = 'Cabecalho da devolucao ' + convert(varchar(12), @numnota) + ' nao foi gravado (ENT_NOTA); item nao integrado.'
		   raiserror(@msg, 16, 1)
		   return
		end

		select @qtsaldo = sum(QTCOMP - COALESCE(QTDEVOL,0))
		  from MOV_ITSAIDA
		 where CODFIL = @codfilsai and TPNOTA = @tpnotasai and NUMNOTA = @numnotasai
		   and DTNOTA = @dtnotasai and SERIE = @seriesai and CODITPROD = @coditprod
		if @qtsaldo is null
		begin
		   set @msg = 'Produto ' + convert(varchar(12), @coditprod) + ' nao esta na nota de saida ' + convert(varchar(12), @numnotasai) + ' serie ' + isnull(@seriesai, '') + '.'
		   raiserror(@msg, 16, 1)
		   return
		end
		if @qtsaldo < @qtcomp
		begin
		   set @msg = 'Produto ' + convert(varchar(12), @coditprod) + ': quantidade devolvida ' + convert(varchar(20), @qtcomp) + ' maior que o saldo da venda ' + convert(varchar(20), @qtsaldo) + '.'
		   raiserror(@msg, 16, 1)
		   return
		end

		set @restante = @qtcomp

                                DECLARE CR_CONSULTA_ITENS CURSOR FOR
								SELECT MOV_ITSAIDA.CODITPROD , MOV_ITSAIDA.ITEM , QTCOMP - COALESCE(QTDEVOL,0), MOV_ITSAIDA.VLTOTAL / QTCOMP, COALESCE(QTEMB,1), COALESCE(CODEMBAL,0) FROM MOV_ITSAIDA   
								WHERE 1=1 AND  CODFIL =  @codfilsai AND  TPNOTA =  @tpnotasai 
								AND  NUMNOTA =  @numnotasai AND  DTNOTA = @dtnotasai AND  SERIE = @seriesai and CODITPROD = @coditprod
								AND QTCOMP - COALESCE(QTDEVOL,0) > 0
								ORDER BY ITEM
								OPEN CR_CONSULTA_ITENS
									FETCH NEXT FROM CR_CONSULTA_ITENS INTO @coditprod, @item , @qtsaldo, @precounit, @conversao, @codembal
										WHILE @@FETCH_STATUS = 0 AND @restante > 0
											BEGIN

							set @qtitem = case when @restante < @qtsaldo then @restante else @qtsaldo end
							set @vltotItem = round(@precounit * @qtitem, 2)

                            
						    set @codprod = (select MAX(codprod) from CAD_ITPROD where CODITPROD = @coditprod)


							-- select custo 
							SELECT @cmup = CMUP , @cue = CUE  FROM VEN_PRODFIL   WHERE 1=1 AND  CODFIL =  8 AND  CODPROD =  @codprod


						    SELECT @FISICO = FISICO, @RESFIS = RESFIS  FROM CAD_PRODLOC  WHERE 1=1 AND CODFIL = @codfil AND TPDEPOS =  @tpdep AND CODITPROD =  @coditprod

							SELECT @totestoque = SUM(FISICO + TECNICO + MOSTRUARIO) FROM CAD_ITPROD ITP, CAD_PRODLOC LOC, CAD_FILIAL CF  WHERE 1=1 AND ITP.CODITPROD = LOC.CODITPROD AND LOC.CODFIL = CF.CODFIL AND ITP.CODPROD = @codprod AND CF.CODFILCUST = 8

							--entrada de estoque
							exec SPU_PROLOCI 1, @codfil, @tpdep, @coditprod, @qtitem, 0, 0, 0, 0, 0, 0, 0, 0, NULL , 0, @data, @qtitem, @tpnota, @numnota, 0, 0, 0, 0, 0

							
							--insere na mov_extrato a entrada
							INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD, FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS, RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC ) 
							VALUES ( @codfil, 0,@numnota, GETDATE(),@tpnota, 'E', 5,@coditprod, @fisico, @resfis, 0, 0, 0, 0, 0, 0, 0,@qtitem, 'FISICO;', 'N', @fisico+@qtitem, @resfis, 0, 0, 0, 0, 0, 0, 0, @codfil, GETDATE(), 'GRAVAITENSNFENTRADA', '', 'REALIZADO PELO INTEGRADOR FIKON' )

							-- inserindo itens da entrada
							INSERT  INTO ENT_ITENT(CODFIL, TPNOTA, CODREMET, SERIE, NUMNOTA, CODITPROD, NUMPEDCOMP, ITEM, DTNOTA, FILDEST, PRECOUNIT, ALIQICM, VLIPI, PORCIPI, SITUACAO, QTCOMP, QTRECEB,    QTEMBAL, QTESTOQUE, CUSTANT, CODEMBAL, CODPRODDF, STATUS, CUSTANTI, VLDESCONTO, LOCAL,    VLDESPFIN, VLICM, VLDESPESAS, VLCONHEC, VLICMRET, QTDEVOL, VLISENTO, VLOUTRAS,    QTCONSIG, VLBASEICMS,  VLNTRIBUT, TOTESTOQUE,       CODVENDR,   ALIQICMRED, ALIQICMSUB, ALIQICMSUBUF, VLBASEICMSSUB, CONVERSAO, VLICMF, VLICMRETF, VLISENTOF,       VLOUTRASF, VLBASEICMSF, VLNTRIBUTF, VLBASEICMSSUBF, QTSALDO, CODCONJU, DESCCOMPLE, VLICMFRT, VLICMSUBREC, COMPLEMENTO, VLOUTRASIPI, VLBASEIPI, VLISENTOIPI, FLATUALIZAPRECO, CODREMETNF, SERIENF,   CMUP,     ALIQIRF, VLDIVIPI, FLREPLICA, CODITCONJU, QTORIG,  HRHORA,      VLPISSUB, VLCOFSUB, CODBARRA, VLDESPACES,  VLFRETE,  VLDESCITEMRAT, VLISS, VLOUTDESP, VLSEGURO, VLSUPINF, VLTOTITEM,   CTF, VLDESCITEM,    VLTOTAL,    QTRETARMAZEM, VLTOTIPI, VLDESPRAT, DPI, CODNATOP, CODNATOPDIF, CODNATOPCOMPL, CODNATOPDIFCOMPL, QTAVARIA, CONDPGTO, VLFUNRURAL, FLAPURACOMISS, FLDEVOLAUTOM, CUE, OBSFISCAL, VLTOTBASEIPI, ALIQINSS, VLBASEINSS, VLINSS, VLIRRF, CODFILANEXO, CODPALLET, FLCROSSDOCKING, CODPRESTSERV, DESCPRESTSERV, VLBASEICMSSUBC, VLICMRETC, VLJUROSVENDA, VLICMSANTEC, MEDGER, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, VLPIS, VLCOFINS, VLBASEICMD, VLICMD, VLIPIC, VLTOTIPIC, VLICMSGARANTIDO, ALIQCSLL, VLBASECSLL, VLCSLL, VLPIN, PORCIPIENT, VLSUFRAMA, CMUPANT, PPIS, PCONTSOC, PADM, VLICMEG, VLBASEICMEG, VLJUROSFIN, VLJUROS, TABELA, VLICMORIGREPI, VLBASEICMORIGREPI, VLICMREPI, VLFRETETERC, VLICMSFRETETERC, DTVALIDADE, ALIQICMDIF, VLBASEICMDIF, VLICMDIF, VLICMDESCONTOF, VLDESCNOTA, VLPISDESCONTOF, VLCOFDESCONTOF, VLICMCREDITO, ALIQICMCREDITO, CUEPIN, PPIN, TXFUNRURAL, VLBASEPIS, VLBASECOFINS, CODDEVOL, PERCICMREDPISCOFINS, VLBASEICMSGARANTIDO, CUSTOGER,   DTATUEST, ALIQICMDIFANTEC, VLBASEICMDIFANTEC, VLICMDIFANTEC, VLBASEICMSATIVO, ALIQICMSATIVO, VLICMSATIVO, ICMPRESUMIDO, ALIQICMPRES, ICMPRESUMIDOF, CUEI , FLNFCOMPL , ALIQICMREDUF , FLESTOQUE , ALIQICMSGARANTIDO, CSTCOFINS, CSTPIS , ALIQPCTM, VLBASEICMSANTEC, ALIQICMSANTEC, FLREATACBA, VLNTRIBUTD , DESCUNIDTRIBUTAVELNF, FATORCONVTRIBUTAVELNF, VLICMRETV, ORIGEMPROD, ALIQICMCARGALIQST, ALIQFECEP, VLFECEP , VLICMRETSIMPFAT, CUETRANSF, CMUPTRANSF, ALIQICMPART, VLFECEPF, VLFECEPSTF, VLFECEPST, VLICMPARTUFF, VLICMPARTUF, VLICMPARTF, VLICMPART, FLFECEPADIC, CEST , CUETRANSFSAI, CMUPTRANSFSAI, ALIQICMUF, CSTIPI, CODIGO53, CODIGO511, VLAJUSTEITEM, ALIQFECEPST, VLBASEFECEPSTF, VLBASEFECEPF, VLBASEICMPARTUFF , CODIGO52, CODIGO56, VLBASESTRETANT, VLICMSTRETANT, ALIQICMSTRETANT, VLBASEFCPSTRETANT, ALIQFCPSTRETANT, VLFCPSTRETANT, FLPAUTAPRECO, VLBASEICMSEFETIVO, VLICMSEFETIVO , ALIQFEEFMT, VLBASEFEEFMT, VLFEEFMT, VLFEEFMTF, VLSUBSTITUTOSTRETANT , VLICMSDESON, CODMOTDESICMS, VLICMOPERACAO, ALIQICMDIFERIMENTO, VLICMDIFERIDO, VLFECEPSTGARANTIDO, VLICMOPERSTF, VLFECEPOPERSTF, VLNTRIBUTUF , VLDESCBASEPIS, VLDESCBASECOFINS, DESCRPRODNFE, CUSTORE, CUE_RE6763, CMUP_RE6763, CODITPRODABENEF , CLASTRIBCBS , CLASTRIBIBS, CLASTRIBIS, CSTCBS, CSTIBS, CSTIS , VLBASECBS, ALIQCBS, VLCBS, VLBASEIBS, ALIQIBS, VLIBS, VLBASEIBSMUN, ALIQIBSMUN, VLIBSMUN, VLBASEIS, ALIQIS, VLIS , PERCREDUTOR) 
							VALUES ( @codfil, @tpnota, @codcli, @serie, @numnota, @coditprod, NULL, @item, @dtnota, NULL, @precounit, 0, 0, 0, NULL,                                             @qtitem,    @qtitem, NULL,    @fisico,   NULL,      @codembal,       NULL,      1,       NULL,       0,    @local,        NULL,    0,      NULL,        0,        0,        0,        0,   @vltotItem,    NULL,        0,          0,        @totestoque,   @codvendr  ,        0,          0,           0,            0,       @conversao,        0,       0,           0,   CASE WHEN @qtitem <> 0 THEN ROUND(@vltotItem / @qtitem, 4) ELSE 0 END,       0,          0,             0,         0,        NULL,     NULL,       0,         0,          NULL,        0,            0,          0,           NULL,          0,       NULL,    @cmup,        0,       NULL,     NULL,      NULL,       0, {FN CURTIME()},    0,        0,       NULL,       0,        NULL,         0,          0,      0,          0,       0,       @vltotItem, 0,       0,       @vltotItem,        0,          0,        0,      0,      10,       NULL,          0,              NULL,        NULL,      NULL,      0,           NULL,        NULL,      @cue,  NULL,          0,         NULL,      NULL,    NULL,   NULL,     NULL,        NULL,        NULL,             0,           NULL,            0,         0,             NULL,       NULL,    NULL,        NULL,             NULL,        NULL,    NULL,       0,         0,   NULL,     NULL,          NULL,        NULL,      NULL,     NULL,  NULL,     NULL,      NULL,     NULL,    0,       0,    NULL, NULL,        NULL,       NULL,    NULL,      0,         NULL,           NULL,           NULL,      NULL,            NULL,       NULL,        NULL,        NULL,      NULL,         NULL,         NULL,        NULL,           NULL,             NULL,       NULL,       NULL,   NULL,    NULL,      NULL,       NULL,         NULL,             NULL,               NULL,       NULL,     GETDATE(),        NULL,          NULL,                NULL,         NULL,           NULL,        NULL,         NULL,         NULL,          NULL,   NULL,'N',          NULL,         NULL,            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 'N', NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 0, 0, 0, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)


							INSERT INTO ENT_ITNOTASAI (CODFIL, TPNOTA, NUMNOTA, SERIE, CODREMET, CODFILSAI,  TPNOTASAI,      NUMNOTASAI,   SERIESAI,   DTNOTASAI,     CODITPROD,      QTDEVOL,   STATUS, VLDESCFRETE, ITEM,     DTNOTA,  VLRESTSEG, VLESTORNOSEG, VLIOFSEG, TPVIGENCIASEG) 
							VALUES (                  @codfil,   26,   @numnota, @serie,  @codcli,  @codfilsai,   @tpnotasai,   @numnotasai,  @seriesai,   @dtnotasai,     @coditprod,   @qtitem,    NULL,       NULL,    @item,   @dtnota,   NULL, NULL, NULL, NULL)

	


							-- item todo devolvido = 8, parcial = 7 (antes invertido)
							set @status = case when @qtsaldo - @qtitem <= 0 then 8 else 7 end

							  UPDATE MOV_ITSAIDA  WITH (READCOMMITTED) SET   STATUS =  @status, QTDEVOL =  COALESCE(QTDEVOL,0) + @qtitem  WHERE 1=1 AND CODFIL =  @codfilsai AND TPNOTA = @tpnotasai AND NUMNOTA =  @numnotasai AND DTNOTA =  @dtnotasai AND SERIE =  @seriesai AND CODITPROD =  @coditprod AND ITEM = @item

							set @restante = @restante - @qtitem


						FETCH NEXT FROM CR_CONSULTA_ITENS INTO
					@coditprod,
					@item,
					@qtsaldo, @precounit, @conversao, @codembal;

			END; -- Fecha WHILE CR_CONSULTA_ITENS

			CLOSE CR_CONSULTA_ITENS;
			DEALLOCATE CR_CONSULTA_ITENS;

			if @restante > 0
			begin
			   set @msg = 'Produto ' + convert(varchar(12), @coditprod) + ': sobrou ' + convert(varchar(20), @restante) + ' sem item de venda para devolver.'
			   raiserror(@msg, 16, 1)
			   return
			end
GO

SET NOEXEC OFF;
GO

-- Conferência: as 2 procedures devem ter o ajuste e as cópias devem existir.
SELECT o.name, o.modify_date,
       CASE WHEN o.name NOT LIKE '%[_]BKP[_]%'
            THEN CASE WHEN CHARINDEX('script 18', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script18
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_INTEGRA_DEVOLUCAO', 'SP_FIKON_INTEGRA_DEVOLUCAO_BKP_SCRIPT18',
                  'SP_FIKON_INTEGRA_ITEM_DEVOLUCAO', 'SP_FIKON_INTEGRA_ITEM_DEVOLUCAO_BKP_SCRIPT18')
 ORDER BY o.name;
GO
