/*
  13 - Modelo da nota (NF-e 55 x NFC-e 65) pela chave de acesso, e não mais por serie = '1'  -  16/11/2026
  BASE: DEV  (DB-TREINO 10.1.5.226), banco dbgemco.
  Este arquivo traz as procedures COMPLETAS da DEV. Para a outra base use o outro script 13.

  Problema:
    As procedures de integração da FIKON decidiam o modelo da nota só pela série:
        if (@serie = '1') -> modelo 55 (NF-e), STATUSNFE 2
        else              -> modelo 65 (NFC-e), STATUSNFE 3
    A FIKON pode mandar NF-e com série diferente de 1 (2, 10...), que seria gravada como NFC-e.
    Desde o ajuste do Integrador/ApiAcal de 16/11, a NFC-e chega com série "U" + 2 dígitos (ex.: "U01").

  Regra nova (função dbo.FN_FIKON_MODELO_NF, criada por este script):
    1. Chave de acesso válida (44 dígitos): o modelo é o que está na chave, posições 21-22 ("55" ou "65").
    2. Sem chave válida: série começando com "U" -> 65 (cupom); qualquer outra -> 55 (NF-e).

  O que mudou em cada procedure (o resto é o texto atual da DEV, conferido por hash SHA-256):
    - SP_FIKON_INTEGRA_MOV_SAIDA (cabeçalho do faturamento) e SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA (cabeçalho do
      cupom):
        if(@serie='1')  ->  set @modelonf = dbo.FN_FIKON_MODELO_NF(@chave, @serie)  +  if(@modelonf = '55')
    - SP_FIKON_INTEGRA_MOV_ITSAIDA (itens do faturamento), que não recebe a chave: usa a CHAVENFE do
      cabeçalho da própria nota.
        * modelo do item: a mesma regra;
        * "update mov_itped set tpped='P'": só quando a nota for NF-e (modelo 55).
    - SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA não muda: desde o script 09 ela lê o MODELONF do cabeçalho.

  Observação sobre o DEV: as procedures de faturamento daqui são uma versão anterior à da produção.
  A SP_FIKON_INTEGRA_MOV_SAIDA não preenchia o @modelonf (ficava sempre '55'); com o ajuste passa a preencher.
  A SP_FIKON_INTEGRA_MOV_ITSAIDA não tem o filtro STATUS = 5 nem o cálculo de CBS/IBS da produção.
  Este script mantém essas diferenças: só troca a regra do modelo.

  Como rodar: no SSMS, conectado na DEV, banco dbgemco, executar o script INTEIRO (F5).
    - O 1º bloco confere que as procedures estão na versão esperada desta base. Se alguma estiver
      diferente, o script para (SET NOEXEC ON) e nada é alterado.
    - Depois guarda as versões atuais como <nome>_BKP_SCRIPT13, cria a função e aplica os ALTERs.
  Para voltar atrás: abrir a <nome>_BKP_SCRIPT13, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @erro varchar(1000) = '';
DECLARE @def nvarchar(max);

-- SP_FIKON_INTEGRA_MOV_SAIDA: versão atual da DEV (SHA-256 0E6B9F22B0F6EB23...) ou já com o script 13
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_SAIDA'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_INTEGRA_MOV_SAIDA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0x0E6B9F22B0F6EB23922749D913EBA9A7589B6A3A1846D3F5A5F9D04F65353902 AND CHARINDEX(N'script 13, 16/11/2026', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_MOV_SAIDA esta numa versao diferente da esperada para esta base. ';

-- SP_FIKON_INTEGRA_MOV_ITSAIDA: versão atual da DEV (SHA-256 7A45FDAC0D535C51...) ou já com o script 13
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_INTEGRA_MOV_ITSAIDA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0x7A45FDAC0D535C51AAD6FF41B70A4876936777350839A5E284E5CEAA641D1F46 AND CHARINDEX(N'script 13, 16/11/2026', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_MOV_ITSAIDA esta numa versao diferente da esperada para esta base. ';

-- SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA: versão atual da DEV (SHA-256 7AA936ADD96F5466...) ou já com o script 13
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0x7AA936ADD96F5466E9043FF16D761BC6FAC56808749BE4DC03CA8AB3F765CE17 AND CHARINDEX(N'script 13, 16/11/2026', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA esta numa versao diferente da esperada para esta base. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    SET NOEXEC ON;   -- os blocos seguintes não são executados
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_SAIDA_BKP_SCRIPT13') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_SAIDA')), N'[dbo].[SP_FIKON_INTEGRA_MOV_SAIDA]', N'[dbo].[SP_FIKON_INTEGRA_MOV_SAIDA_BKP_SCRIPT13]');
        EXEC sys.sp_executesql @def;
    END
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT13') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA')), N'[dbo].[SP_FIKON_INTEGRA_MOV_ITSAIDA]', N'[dbo].[SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT13]');
        EXEC sys.sp_executesql @def;
    END
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT13') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA')), N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA]', N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT13]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_SAIDA_BKP_SCRIPT13') IS NULL
       OR OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT13') IS NULL
       OR OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT13') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar as copias de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copias guardadas: <nome>_BKP_SCRIPT13.';
END
GO

/* ===================== 2. Função da regra do modelo ===================== */
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

IF OBJECT_ID('dbo.FN_FIKON_MODELO_NF') IS NULL
BEGIN
    RAISERROR('Nao foi possivel criar a funcao dbo.FN_FIKON_MODELO_NF. As procedures nao foram alteradas.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ===================== 3. SP_FIKON_INTEGRA_MOV_SAIDA (completa) ===================== */
ALTER proc [dbo].[SP_FIKON_INTEGRA_MOV_SAIDA] 

@numpedven numeric(12,0),
@numnota numeric(12,0),
@serie varchar(3),
@chave varchar(44),
@hrhora datetime 

 as

 
BEGIN TRY 

declare @codfil int
declare @dtnota date = getdate()
declare @dtemissao date = getdate()
declare @dtpedido date
declare @dtentrega date
declare @condpgto  varchar(3)
declare @estado varchar(2)
declare @codcli  numeric(12,0)
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
declare @vlcbs numeric(15,2)
declare @vlbaseibs numeric(15,2)
declare @vlibs numeric(15,2)
declare @vlbaseibsmun numeric(15,2)
declare @vlibsmun numeric (15,2)
declare @tpnota varchar(4)
declare @statusnfe int = 0


-- Modelo pela chave de acesso (script 13, 16/11/2026); antes: serie = '1'.
set @modelonf = dbo.FN_FIKON_MODELO_NF(@chave, @serie)
if(@modelonf = '55')
begin
set @statusnfe=2
end
  else
    set @statusnfe=3

DECLARE CR_INSERE CURSOR FOR

SELECT top 1
    MOV_PEDIDO.CODFIL,
    MOV_PEDIDO.CODVENDR,
    --MOV_PEDIDO.TPPED,
    --MOV_PEDIDO.FILORIG,
    MOV_PEDIDO.CONDPGTO,
    MOV_PEDIDO.CODCLI,
    MOV_PEDIDO.DTPEDIDO,
    MOV_PEDIDO.DTENTREGA,
    MOV_PEDIDO.ENDCOB,
    MOV_PEDIDO.ENDENT,
    --MOV_PEDIDO.AUTORIZAC,
    --MOV_PEDIDO.NUMLOTE,
    MOV_PEDIDO.PRACA,
    --MOV_PEDIDO.VLDESPACES,
    --MOV_PEDIDO.VLOUTDESP,
    --MOV_PEDIDO.VLDESPFIN,
    MOV_PEDIDO.VLDESCONTO,
    MOV_PEDIDO.VLENTRADA,
    MOV_PEDIDO.VLFRETE,
    --MOV_PEDIDO.VLSEGURO,
    MOV_PEDIDO.VLMERCAD, 
   -- MOV_PEDIDO.SITCARGA,
    MOV_PEDIDO.TPNOTA,
    MOV_PEDIDO.VLTOTAL,
    MOV_PEDIDO.NOME,
    MOV_PEDIDO.VLBASEICMS,
    MOV_PEDIDO.VLVDVISTA,
    MOV_PEDIDO.VLVDLIQ,
    MOV_PEDIDO.QTPRC,
   -- MOV_PEDIDO.TPFRETE,
    MOV_PEDIDO.ENDFAT,
   -- MOV_PEDIDO.VLTOTALIND,
    MOV_PEDIDO.OBS,
    --MOV_PEDIDO.CODUSER,
    MOV_PEDIDO.VLPRC,
    isnull(MOV_PEDIDO.VLICM,0),
    isnull(MOV_PEDIDO.VLBASEICMSSUB,0),
    isnull(MOV_PEDIDO.VLICMRET,0),
    --MOV_PEDIDO.VLISENTO,
    isnull(MOV_PEDIDO.VLOUTRAS,0),
	ecli.ESTADO

FROM MOV_PEDIDO
INNER JOIN MOV_PEDIDO_COMPL
    ON MOV_PEDIDO_COMPL.CODFIL    = MOV_PEDIDO.CODFIL
   AND MOV_PEDIDO_COMPL.TIPOPED   = MOV_PEDIDO.TIPOPED
   AND MOV_PEDIDO_COMPL.NUMPEDVEN = MOV_PEDIDO.NUMPEDVEN
   inner join cad_endcli ecli  on
   ecli.codcli=MOV_PEDIDO.codcli 
   and ecli.CODEND = MOV_PEDIDO.ENDFAT

WHERE 1=1
  AND MOV_PEDIDO.TIPOPED = 0
  AND MOV_PEDIDO.NUMPEDVEN = @numpedven;

   OPEN CR_INSERE
	  FETCH NEXT FROM CR_INSERE INTO @codfil, @codvendr, @condpgto, @codcli,  @dtpedido, @dtentrega, @endcob, @endent, @praca, @vldesconto,@vlentrada, @vlfrete,@vlmercad,@tpnota, @vltotal, @cliente, @vlbaseicm, 
	  @vlvdvista, @vlvdliq, @qtprc, @endfat, @obs, @vlprc, @vlicm,@vlbaseicmssub, @vlicmret,@vloutras,@estado
	  
	     WHILE @@FETCH_STATUS = 0
	 
		 BEGIN

		 Begin tran

					INSERT  INTO MOV_SAIDA (CODFIL, TPNOTA, NUMNOTA,  SERIE,     DTNOTA, TIPOPED, NUMCTRL,   DTEMISSAO,    DTPEDIDO,   DTCANCEL,  DTENTREGA,    CONDPGTO,    ESTADO,   GUIA, ALIQICM, CODNATOP,     NUMPEDVEN,    CODCLI,    CODVENDR, NUMCXA, CODTRANSP, CODMENSAG, ZONAENT, SEQENT, ENDCOB,      ENDENT,     FLENTRET, LOCAL, ORIGEM, LOTE, PESO,   PRACA,  SETOR, SITUACAO, TPOCORR, TPPEND, TPTRANS, AUTORIZAC, NFPRESENT, OBS, VLDESPACES, VLACRESCIM,    VLBASEICMS,         VLDESCONTO,          VLDESPFIN, VLDESPSICM,    VLFRETE,    VLICM,     VLICMRET,  VLIPI, VLMERCAD,    VLOUTDESP, VLSEGURO, VLENTRADA, CUBAGVEIC, CUBAGNF, STATUS, CODCLIPRES, FILPED,     NUMCONTRA, DEPTVD, VLISENTO, VLOUTRAS, DATCOT, LOTCOT, NUMLAN, VLBASEIPI, VLTOTAL, VLREDICMS, FLRICMS, REBATE, QTINDICE, PESOLIQ, VLBASEICMSSUB, VLISS, CODAWBDET, CODAWB, CODCOURIER, AEROORIG, AERODEST, DTDARF, DTEXP, FLSPC, VLII, CODSEGURADORA, NUMPEDCLI, CODMODAL, VLVDLIQ, CODNATOPCLI, FLINTEGRACAO, DIGCONTRAFIN, CODDEVOL,    HRHORA,           HRDURACAO, CIFFOB, CODFILSOLIC, TPFRETE,  ENDFAT, FLNFMANUAL, CODOCORENT, CODTRANSPRED, NUMCONTRAFIN, VLJUROSFIN, PJUROS,        DTATUEST,     FLATUEST, FLDUPLICATA, VLTOTALIND, SEXO, IDADE, CODFUNC, HRHORAINI, DTLIBPED, FLTPVENDA, CODFILSIMPFAT, TPNOTASIMPFAT, NUMNOTASIMPFAT, SERIESIMPFAT, CODFILPDV, DTNOTAPDV, FLNOTAPDV, NUMNOTAPDV, NUMPDV, SERIEPDV, TPNOTAPDV, CONTROLE,     NOME,                     CODCLIENT, ENDCLIENT, CODUSER,       VLAGREGACRC, VLISENTOIPI, VLOUTRASIPI, QTPRC,  VLPRC,  QTVOLUME, FLFISCAL, OBSFISCAL, DTVALID, FLREPLICA,  IDENTPROC,  CODNATOPDIF, CODNATOPCOMPL, NUMNOTADEBITO, NUMNOTAENT, SERIEENT, FLINSTALATERCEIRO, VLFRETETERCEIRO, FLINTFIN, DTALTERACAO, USERIDALT , VLIRRF, TPCONTRATO, SERIECONTRAFIN, NOMERECEB, DTRECEB, HRRECEB, DTSIMPFAT, VLJUROS, CODCLIPUBLICIDADE, CODENDCLIPUBLICIDADE, NUMCTRLPART, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, NRSERIEECF, VLBASEICMD, VLICMD,  VLPISCOFINSCSLL, FLDEVOL, CODTRANSP2, FLSEGURO, VLDESCNOTA, VLBASEICMORIGREPI, VLICMORIGREPI, VLICMREPI, FLTRANSFANEXOAUT, TPPGTO, INTEGRACRC, CODFILORIG, NUMNOTAORIG, SERIEORIG, TPNOTAORIG, DTNOTAORIG, VLTOTALSIMPFAT, VLICMDESCONTO, TOTCUPOMPROMOCIONAL, VLICMTRANSF, ANOMESAPU, VLTAC, CARENCIA, VLTARBANCARIA, NUMOSMONTAG, STATUSOSMONTAG, VLPISDESCONTO, VLCOFDESCONTO, MODELONF, VLBASEICMSDIFSAI, VLICMDIFSAI, NUMORC, DTPREVRETMET, DTUSEREEMISAO, CODUSEREEMISAO, DTAUTORIZACAONFE, NUMNFE, DIGNFE, STATUSNFE, DTCANCELAMENTONFE, NSU, DTIMPRESSAO, DATENT, ESTADOPLACA, ESTADOPLACACARRETA, PLACACARRETA, PLACAVEIC  ,CODNATOPDIFCOMPL, VLTOTPISRET, VLTOTCSLLRET, VLTOTIRRET, VLTOTCOFINSRET, VLNTRIBUTD, VLICMRETV , VLICMCREDITO, VLIBPT, ALIQIBPT,     DATAHORAUTC,    FLMOTORDEPROMOCOES, CODOPER, CHAVEIBPT, FONTEIBPT, ALIQIBPTEST, VLIBPTEST, ALIQIBPTMUN, VLIBPTMUN,                 CHAVENFE,                               CODMODELOSEFAZENTNFE, CODFILDESTENTNFE, CODREMETENTNFE, SERIEENTNFE, DTNOTAENTNFE, NUMNOTAENTNFE, CHAVENFEENTNFE, SEQINVDATA, VLFECEP, VLFECEPST, VLICMPARTUF, VLICMPART, CODCONTR,   CHAVENFEREF,NRSERIEECFREF, FLUTILSAIDA, VLICMSDESON, CODFORNEINTERMEDIADOR, FLPAGINTERMEDIADOR, CODPROFISSAOCASHBACK, VLBASECBS,   VLCBS,      VLBASEIBS,     VLIBS,         VLBASEIBSMUN,                   VLIBSMUN,     VLBASEIS,      VLIS, PERCREDUTOR , tpajuste, FLEXCFCPBCPISCOFINS, FLEXCICMSBCPISCOFINS) 
					VALUES (                 @codfil, @tpnota,  @numnota, @serie,    @dtnota,   0,    NULL,     @dtemissao,    @dtpedido,    NULL,   @dtentrega,    @condpgto,   @estado,  NULL,  NULL,     NULL,        @numpedven,  @codcli,   @codvendr,   NULL,     0,        0,        NULL,   NULL,    @endcob,    @endent,     NULL,     1,       0,  null, @peso, @praca,   0,     NULL,      NULL,   NULL,   NULL,    '0',        NULL,  @obs,     0,          NULL,       @vlbaseicm,         @vldesconto,            0,       NULL,      @vlfrete,    @vlicm,    @vlicmret,    0,      @vlmercad,  0,           0,   @vlentrada,       NULL,       .01,    2,         0,     @codfil,         0,      NULL,    0,     @vloutras, NULL,   NULL,   NULL,     0,     @vltotal,    NULL,     NULL,    NULL,   NULL,    @peso,  @vlbaseicmssub,  0,      NULL,     NULL,     NULL,      NULL,     NULL,   NULL,   NULL,  NULL, NULL,       0,           NULL,     NULL,     0,         NULL,       NULL,           0,          NULL,      @hrhora ,           NULL,         NULL,   NULL,      3,    @endfat,      'N',         0,        NULL,           0,           0,           0,         @hrhora,         'S',      NULL,       NULL,      NULL, NULL,   0,         NULL,    NULL,       NULL,         0,             0,            0,             NULL,        NULL,       NULL,     NULL,     NULL,     NULL,     NULL,      NULL,   'AC12',    @cliente,                         0,       NULL,    @coduser,        0,             0,           0,    @qtprc, @vlprc,     0,       NULL,      NULL,     NULL,     NULL,    @identproc, @codnatop,       NULL,         NULL,          0,        NULL,           NULL,               0,           NULL,     NULL,        NULL,     0,        'C',          '0',         NULL,     NULL,     NULL,   NULL,       0,             0,                 0,               NULL,             0,               0,             NULL,   @vlbaseicmd , @vlicmd,    0,             'N',     0,         'N',        0,               0,             0,            0,           NULL,         1,       'N',         0,         0,           NULL,       0,        NULL,          0,             0,              0,                    0,        0,       0,       0,            0,         NULL,          NULL,           0,              0,      @modelonf,       0,                0,       0,        NULL,         NULL,           NULL,            NULL,        NULL,   NULL,    @statusnfe,           NULL,        NULL,    NULL,    @dtnota ,     NULL,           NULL,             NULL,       NULL,    @codnatopdifcompl,     0,           0,           0,            0,            0,          0,            0,      NULL,    NULL,       @DATAHORAUTC  ,        NULL,           0,       NULL,      NULL,        NULL,      NULL,      NULL,       NULL,         @chave,                                     NULL,                 NULL,              NULL,        NULL,          NULL,        NULL,             NULL,       0,         0,        0,          0,          0,           2,           NULL,        NULL,         NULL,        NULL,            NULL,                  NULL,                0,            @vlbasecbs,  @vlcbs,    @vlbaseibs,     @vlibs,        @vlbaseibsmun,         @vlibsmun,        0,         0,        0  ,        'F'       ,  'N',                      'S'       )





				  exec SP_FIKON_INTEGRA_MOV_ITSAIDA @numpedven, @numnota,@serie,@codfil ,@codcli,@hrhora, @estado


	
   
   
     FETCH NEXT FROM CR_INSERE INTO  @codfil, @codvendr, @condpgto, @codcli,  @dtpedido, @dtentrega, @endcob, @endent, @praca, @vldesconto,@vlentrada, @vlfrete,@vlmercad,@tpnota, @vltotal, @cliente, @vlbaseicm, 
	  @vlvdvista, @vlvdliq, @qtprc, @endfat, @obs, @vlprc, @vlicm,@vlbaseicmssub, @vlicmret,@vloutras,@estado
	       


  END

  CLOSE CR_INSERE
  DEALLOCATE CR_INSERE 




  
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

/* ===================== 4. SP_FIKON_INTEGRA_MOV_ITSAIDA (completa) ===================== */


 ALTER PROC [dbo].[SP_FIKON_INTEGRA_MOV_ITSAIDA] 


 @numpedven numeric(12,0),
 @numnota numeric(12,0),
 @serie varchar(3),
 @codfil int,
 @codcli numeric(12,0),
 @hrhora datetime ,
 @estado varchar(2)

as

BEGIN TRY 

declare @dtnota date = getdate()
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
  MOV_ITPED.CTF, VEN_PRODFIL.CMUPI , VEN_PRODFIL.CUE,MOV_ITPED.CODBARRA 
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
 and MOV_ITPED.TPPED='R'
 order by mov_itped.ITEM

  OPEN CR_INSERE_ITENS
	  FETCH NEXT FROM CR_INSERE_ITENS INTO  @codvendr,@tpnota, @coditprod, @item, @qtcomp,@precounit,@aliqicm, @ALIQICMSUB,@cubagem,@dpi,@UNEMBAL,@vlfrete,@cmup,@codsitprod,
	  @vlbaseicm,@vlicm, @vlbaseicmssub,@vlicmret,@vldescitem,@vldescitemrat,@qtemb,@vltotal,@ctf,@cmupi,@cue,@codbarra
	  
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

INSERT INTO MOV_ITSAIDA (CODFIL,  TPNOTA,  NUMNOTA,    DTNOTA,   SERIE,   CODITPROD,  ITEM,  QTCOMP,  PRECORDZ, PRECOUNIT,  ALIQICM,   ALIQICMSUB, ALIQICMRED, VLIPI, LOCAL, TPDEPOS, PORCIPI, MINUTA,    CUBAGEM, CODASSTEC, DTASSTEC, CODEMBAL,  DPI,    DESCCOMPLE, STATUS,  NUMPEDVEN,  UNEMBAL,  CODCLI,   QTRETORN, PRECJUR, VLFRETE,    QTDEVOL,    PRECOUNITLIQ, VLSUPINF, FLINTEGRACAO, CMUP, MEDGER, HRHORA,  CODSITPROD,   RUA, BLOCO, APTO,  FILPED,   DTPROD, ALIQICMSUBUF, FILORIG,   IDADEPROD, VLBASEICMS,      VLISENTO, VLNTRIBUT, VLOUTRAS,     VLICM,    QTESTOQUE, VLBASEICMSSUB,     VLICMRET,     VLDESCITEM,     VLDESCITEMRAT,   QTSALDO, CODPROM,    QTEMB, VLBASEICMSF, VLISENTOF, VLNTRIBUTF,  VLOUTRASF,   VLICMF, VLBASEICMSSUBF, VLICMRETF, ALIQIRF, VLDESPACES, VLOUTDESP, VLOFERTA, COMPLEMENTO, CRM, VLOUTRASIPI, VLBASEIPI, VLISENTOIPI, FLBXCOMP, QTCONSIG, QTVOLUME, CODITPRODKIT, COMISSPER, COMISSVAL, FLPRODGEN, CODVENDR,     DTVALIDFIM, DTVALIDINI, VLISS,   CODNATOP, CODNATOPDIF,    CODNATOPCOMPL,   CODNATOPDIFCOMPL,       OBSFISCAL, CUEORIG, FLDETALHE, VLTOTITEM,   CTF,   CODPLANOSERV, ALIQICMSFRETE, VLFRETERAT,VLICMSFRETE, VLDESPFIN, VLICMRETFRT, VLSEGURO, VLDESPRAT, VLTOTAL,   CMUPI,  VLTOTIPI, FILPEDARMAZEM, NUMPEDARMAZEM,TIPOPEDARMAZEM, VLBASEICMSUBENT, VLICMRETENT, VLIRRF, DTALTERACAO, USERIDALT, CUE, VLTOTBASEIPI, FLLOTEVENCTO,CODPRESTSERV, DESCPRESTSERV, FLPRODPROCESS, VLJUROSVENDA, VLJUROSFIN, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV,VLBASEICMD,     VLICMD,     PRECOLISTA, ALIQPISCOFINSCSLL,VLPISCOFINSCSLL, PENCARGO, VLJUROS, VLBASEISS, ALIQISS, PRECOORIG, VLDESCNOTA, ALIQICMREPI, VLBASEICMORIGREPI, VLICMORIGREPI,VLICMREPI, ALIQPISSUB, ALIQCOFSUB, VLPISSUB, VLCOFSUB, FLSUBSTINTERNA, QTVENDAKIT, PCONTSOC, VLPPIS, VLPCONTSOC,PPIS, ALIQICMDIF, VLBASEICMDIF, VLICMDIF, VLICMDESCONTOF, VLTAC, CODTECNICO, VLPISDESCONTOF, VLCOFDESCONTOF, ALIQICMDIFSAI, VLBASEICMSDIFSAI, VLICMDIFSAI, NUMORC, CUSTOGER, ALIQICMSATIVO, VLBASEICMSATIVO, VLICMSATIVO, FLATUTRAN, FLPREINDIG, VLPISRET, VLCSLLRET, VLIRRET, VLCOFINSRET, ALIQPCTM, ALIQICMREDUF, VLNTRIBUTD, DESCUNIDTRIBUTAVELNF, FATORCONVTRIBUTAVELNF, VLICMRETV, ALIQICMCREDITO,  VLICMCREDITO, ORIGEMPROD, DESCLICITACAO, ALIQIBPT, VLIBPT, VERSAOIBPT, NUMFCI, CONVERSAO, VLCUSTOIMP, OBSCOMPLPROD, FLESCFISCALDIF, CFOPNOTA, CTFNOTA, CODJUST, CHAVEIBPT, FONTEIBPT, ALIQIBPTEST, VLIBPTEST, ALIQIBPTMUN, VLIBPTMUN,VLICMSRECUPTRANSF, ALIQICMUF, VLICMSSTRECUPTRANSF,  ALIQFECEP , ALIQICMPART, VLFECEPF, VLFECEP,  VLFECEPSTF, VLFECEPST, VLICMPARTUFF, VLICMPARTUF, VLICMPARTF, VLICMPART, FLFECEPADIC, CEST, VLBASEPIS, VLBASECOFINS, CUETRANSF, CMUPTRANSF,CSTIPI, CSTPIS, CSTCOFINS, CODBARRA, VLBASEFECEPF, VLBASEFECEPSTF, ALIQFECEPST, VLBASEICMPARTUFF,  CODIGO53, VLAJUSTEITEM, CODIGO52, CODIGO56, VLBASESTRETANT, VLICMSTRETANT, VLREMGST, VLBASEFCPSTRETANT, ALIQFCPSTRETANT, VLFCPSTRETANT,VLBASEICMSEFETIVO,     VLICMSEFETIVO,  VLICMSGARANTIDO, VLBASEICMSGARANTIDO, VLICMEG, VLBASEICMEG, VLSUBSTITUTOSTRETANT,  VLICMOPERACAO, ALIQICMDIFERIMENTO, VLICMDIFERIDO, VLICMSDESON, CODMOTDESICMS,VLFECEPSTGARANTIDO, VLBASEDESONDIFERF, VLBASEICMUE, VLICMUE, VLBASEICMSSTUE, VLICMSSTUE, VLFECEPSTUE, VLBASEICMMUP, VLICMMUP, VLBASEICMSSTMUP, VLICMSSTMUP, VLFECEPSTMUP, VLICMOPERSTF,      VLFECEPOPERSTF, VLFECEPUE, VLFECEPMUP, VLNTRIBUTUF, VLDESCBASEPIS, VLDESCBASECOFINS, CUSTORE, CUE_RE6763, CMUP_RE6763, VLCASHBACKPROFISCONSTRU, CODITPRODBENEF, CLASTRIBCBS, CLASTRIBIBS, CLASTRIBIS, CSTCBS, CSTIBS, CSTIS,  VLBASECBS,     ALIQCBS,    VLCBS, VLBASEIBS,          ALIQIBS,          VLIBS,  VLBASEIBSMUN,            ALIQIBSMUN, VLIBSMUN, VLBASEIS, ALIQIS, VLIS, PERCREDUTOR  ) 
VALUES (                 @codfil, @tpnota, @numnota, @dtnota,    @serie, @coditprod,  @item, @qtcomp,   NULL,  @precounit,  @aliqicm,  @ALIQICMSUB,        0,         0,    1,     'L',       0,     NULL,  @cubagem,       NULL,     NULL,     0,      @dpi,       NULL,     2,     @numpedven, @UNEMBAL, @codcli,    NULL,      0,      @vlfrete,     0,         @precounit,   0,         NULL,    @cmup,    0,   @hrhora, @codsitprod,  NULL, 0,    NULL,   @codfil,   NULL,     20,        @codfil,     NULL,   @vlbaseicm,           0,        0,    @vloutras,    @vlicm,   @QTESTOQUE,   @vlbaseicmssub,    @vlicmret,  @vldescitem,   @vldescitemrat,      0,       0,     @qtemb,       0,            0,        0,     @VLOUTRASF,     0,          0,            0,       0,         0,          0,       0,          NULL,     0,       0,           0,         0,       NULL,      0,        0,          NULL,        NULL,      NULL,      NULL,    @CODVENDR,      NULL,       NULL,       0,    @codnatop,      NULL,   @codnatopdifcompl, NULL,                 @obsfiscal,    NULL,    NULL,    @vltotal,   @ctf,    NULL,               0,           0,         0,           0,      NULL,         0,        0,       @vltotal, @cmupi,    0,         NULL,         NULL,           NULL,            NULL,          NULL,       0,       NULL,      NULL,  @cue,      0,            'N',          0,           NULL,           'N',           NULL,         0,             0,              0,           @vlbaseicmd,   @vlicmd,     0,             0,                0,             0,        0,        0,        0,   @precounit,    0,             0,             0,              0,         0,           0,           0,        0,          0,         NULL,          0,        0,       0,        0,       0,      0,          0,             0,         0,         0,        0,             0,            0,                0,             0,               0,       0,      NULL,        0,              0,             0,          NULL,       'N',       0,        0,         0,        0,          0,        0,            0,                NULL,                 NULL,            0,             0,              0,          0,           NULL,        NULL,  NULL,     NULL,      NULL,    1,        NULL,           NULL,         NULL,         0,      NULL,    NULL,    NULL,      NULL,       NULL,         NULL,      NULL,        NULL,      NULL,         @aliqicm,        NULL,                0,          0,         0,          0,        0,         0,          0,             0,         0,           0,         'N',     NULL,      0,         0,        NULL,       NULL,     NULL,  NULL,    NULL,   @CODBARRA,      0,            0,              0,            0,              NULL,      NULL,        NULL,    NULL,          0,           0,             0,             0,                0,               0,       @vlbaseicmsefetivo, @vlicmsefetivo,      NULL,                NULL,          NULL,     NULL,                0,              NULL,            NULL,               NULL,         NULL,       NULL,             NULL,           NULL,               0,        0,            0,            0,          0,          0,           0,           0,             0,           0,      @vlicmsefetivo,          0,             0,           0,           0,          0,                0,          0,          0,          0,                  0,                   0,        '000001',   '000001',       NULL,   '000', '000',   NULL, @vlbasecbs,   @vlaliqcbs,  @vlcbs,     @vlbaseibs,      @vlaliqibs,      @vlibs,       @vlbaseibsmun,          0,         0,         0,      0,     0,        0)
  

UPDATE MOV_ITPED  WITH (READCOMMITTED) SET   DTNOTA =  @dtnota, QTEMITIDO =  @qtcomp, STATUS =  6, NUMNOTA =  @numnota, TPNOTA =  @tpnota, QTFAT =  QTFAT + @qtcomp, QTLIB =  QTLIB - @qtcomp, QTCORTE =  case when qtcorte> 0 then QTCORTE - @qtcomp else 0 end  WHERE 1=1 AND MOV_ITPED.CODFIL = @codfil AND MOV_ITPED.NUMPEDVEN = @numpedven AND MOV_ITPED.TIPOPED = 0 AND MOV_ITPED.CODITPROD = @coditprod AND MOV_ITPED.ITEM = @item

exec SPU_PROLOCI 1, @codfil, 'L', @coditprod, @qtcompbaixa, @qtcompbaixa, 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0 

INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,    FISICO,  RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO,    FISICOPOS,         RESFISPOS,       ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG,  DTPROC,           ROTINA,                  COMANDOSQL,                                                                                                                                                                                   IDENTPROC ) 
VALUES ( @codfil, @numpedven,@numnota, GETDATE(),@tpnota,                   'S',     3,    @coditprod, @fisico,  @resfis,     0,         0,      0,       0,      0,         0,           0,       -@qtcomp,      'FISICO;RESFIS;', 'N',   @fisico-@qtcomp,  @resfis-@qtcomp ,         0,           0,         0,        0,           0,              0,             0,         @codfil, getdate(), 'GRAVAITENSNOTAFISCAL', '{CALL SPU_PROLOCI(1, '+convert(varchar,@codfil)+', L, '+convert(varchar,@coditprod)+', -'+convert(varchar,@qtcomp)+', -'+convert(varchar,@qtcomp)+', 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0)} ',                                    'INTEGRADOR FIKON' )


  set @totalPeso= @totalPeso +  (Select sum(PESOLIQ*QTCOMP) from mov_itped  where numpedven=@numpedven and TPPED = 'R' AND CODITPROD=@CODITPROD)


     FETCH NEXT FROM CR_INSERE_ITENS INTO  @codvendr, @tpnota,@coditprod, @item, @qtcomp,@precounit,@aliqicm, @ALIQICMSUB,@cubagem,@dpi,@UNEMBAL,@vlfrete,@cmup,@codsitprod,
	  @vlbaseicm,@vlicm, @vlbaseicmssub,@vlicmret,@vldescitem,@vldescitemrat,@qtemb,@vltotal,@ctf,@cmupi,@cue,@codbarra
	       


  END

  CLOSE CR_INSERE_ITENS
  DEALLOCATE CR_INSERE_ITENS 

 set @totalPedido =  (Select sum(VLTOTITEM+VLFRETE-VLDESCITEMRAT) from mov_itped  where numpedven=@numpedven and TPPED = 'R')


 UPDATE MOV_SAIDA SET VLtotal= @totalPedido, PESO = @totalPeso, PESOLIQ = @totalPeso where numnota=@numnota and numpedven=@numpedven and serie=@serie

 if(select count(*) from  mov_itped where numpedven=@numpedven and TPPED<>'R') > 0
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

/* ===================== 5. SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA (completa) ===================== */
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

-- Modelo pela chave de acesso (script 13, 16/11/2026); antes: serie = '1'.
set @modelonf = dbo.FN_FIKON_MODELO_NF(@chave, @serie)
if(@modelonf = '55')
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
 -- Vendedor (script 12, 16/11/2026): CPF do vendedor da FIKON na VEN_VEND da filial.
 --   Mais de um cadastro com o mesmo CPF: o ativo (STATUS 0) mais recente (antes: erro 512).
 --   Nao encontrado ou CPF nao enviado: grava 0 (antes ficava NULL e o trigger da MOV_ITSAIDA
 --   falhava ao gravar a EST_PRODVEN, onde CODVENDR nao aceita NULL).
 set @codvendr = (select top 1 codvendr from dbgemco..VEN_VEND where CODFIL=@codfil and CGCCPF = @cpfconsultor
                  order by case when STATUS = 0 then 0 else 1 end, codvendr desc)
 if (@codvendr is null)
     set @codvendr = 0
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

-- Conferência: as 3 procedures devem ter o ajuste; a função e as cópias devem existir.
SELECT o.name, o.type_desc, o.modify_date,
       CASE WHEN o.type = 'P' AND o.name NOT LIKE '%[_]BKP[_]%'
            THEN CASE WHEN CHARINDEX('FN_FIKON_MODELO_NF', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script13
  FROM sys.objects o
 WHERE o.name IN ('FN_FIKON_MODELO_NF',
                  'SP_FIKON_INTEGRA_MOV_SAIDA', 'SP_FIKON_INTEGRA_MOV_SAIDA_BKP_SCRIPT13',
                  'SP_FIKON_INTEGRA_MOV_ITSAIDA', 'SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_SCRIPT13',
                  'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA', 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT13')
 ORDER BY o.name;
GO

-- Teste da regra (não grava nada)
IF OBJECT_ID('dbo.FN_FIKON_MODELO_NF') IS NOT NULL
    EXEC sys.sp_executesql N'
SELECT t.descricao, t.serie, dbo.FN_FIKON_MODELO_NF(t.chave, t.serie) AS modelo
  FROM (VALUES (''NFC-e serie U01 (chave mod 65)'', ''U01'', ''23261107201916001716650010000001201073778518''),
               (''NF-e serie 1 (chave mod 55)'',     ''1'',   ''23261107201916001392550010000000231092417994''),
               (''NF-e serie 2 sem chave'',          ''2'',   ''''),
               (''Cupom U04 sem chave'',             ''U04'', NULL),
               (''Cupom serie 444 (chave mod 65)'',  ''444'', ''23261107201916001392654440000000971009960341'')) t(descricao, serie, chave);';
GO
