/*
  29 - Cupom FIKON: NUMNFE, DIGNFE, NUMCOO e NUMCCF como no PDV do Gemco - PRODUÇÃO  -  19/11/2026
  Base: PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  (O DEV não estava acessível ao gerar este script; a versão do DEV será conferida à parte.)

  Problema:
    Nos cupons NFC-e do PDV do Gemco (ex.: DM, séries U03/U04) a MOV_SAIDA tem:
      NUMNFE = número da nota (98704), DIGNFE = dígito verificador da chave (posição 44),
      NUMCOO = código numérico da chave (posições 36-43), NUMCCF = 0.
    A SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA gravava NUMNFE e DIGNFE nulos e nem informava NUMCOO/NUMCCF:
    na tela de consulta de cupons, os da FIKON aparecem com número 0.

  O que muda (procedure completa abaixo): o INSERT na MOV_SAIDA passa a gravar esses 4 campos pela regra
  acima. Nada mais muda. Os cupons já gravados são corrigidos no script 30.

  Como rodar: no SSMS, conectado na PRODUÇÃO, banco dbgemco, executar o script INTEIRO (F5).
    - O bloco 1 confere a versão da procedure (SHA-256 92CE1E60...) e guarda a cópia
      SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT29. Se algo estiver diferente, nada é alterado.
  Para voltar atrás: abrir a cópia _BKP_SCRIPT29, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA'));

IF @def IS NULL
   OR (HASHBYTES('SHA2_256', @def) <> 0x92CE1E60BAE06121BFA9EFF667FE5BAE9E4C880351BB20C0D9DC2ACB55278EDD AND CHARINDEX(N'script 29', @def) = 0)
BEGIN
    RAISERROR('Nada foi alterado: SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA nao existe ou esta numa versao diferente da esperada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT29') IS NULL
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA]', N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT29]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT29') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copia guardada: SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT29.';
END
GO

/* ===================== 2. SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA (completa) ===================== */
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

-- script 29 (19/11/2026): numeracao do cupom como no PDV do Gemco (NFC-e):
--   NUMNFE = numero da nota, DIGNFE = digito verificador da chave (posicao 44),
--   NUMCOO = codigo numerico da chave (posicoes 36-43), NUMCCF = 0. Antes NUMNFE/DIGNFE iam nulos.
declare @numnfe_s29 numeric(9,0) = @numnota
declare @dignfe_s29 numeric(1,0) = case when len(ltrim(rtrim(@chave))) = 44 and ltrim(rtrim(@chave)) not like '%[^0-9]%'
                                        then convert(numeric(1,0), substring(ltrim(rtrim(@chave)), 44, 1)) end
declare @numcoo_s29 numeric(9,0) = case when len(ltrim(rtrim(@chave))) = 44 and ltrim(rtrim(@chave)) not like '%[^0-9]%'
                                        then convert(numeric(9,0), substring(ltrim(rtrim(@chave)), 36, 8)) end


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

     INSERT  INTO MOV_SAIDA (CODFIL, TPNOTA, NUMNOTA,  SERIE,     DTNOTA, TIPOPED, NUMCTRL,   DTEMISSAO,    DTPEDIDO,   DTCANCEL,  DTENTREGA,    CONDPGTO,    ESTADO,   GUIA, ALIQICM, CODNATOP,     NUMPEDVEN,    CODCLI,    CODVENDR, NUMCXA, CODTRANSP, CODMENSAG, ZONAENT, SEQENT, ENDCOB,      ENDENT,     FLENTRET, LOCAL, ORIGEM, LOTE, PESO,   PRACA,  SETOR, SITUACAO, TPOCORR, TPPEND, TPTRANS, AUTORIZAC, NFPRESENT, OBS, VLDESPACES, VLACRESCIM,    VLBASEICMS,         VLDESCONTO,          VLDESPFIN, VLDESPSICM,    VLFRETE,    VLICM,     VLICMRET,  VLIPI, VLMERCAD,    VLOUTDESP, VLSEGURO, VLENTRADA, CUBAGVEIC, CUBAGNF, STATUS, CODCLIPRES, FILPED,     NUMCONTRA, DEPTVD, VLISENTO, VLOUTRAS, DATCOT, LOTCOT, NUMLAN, VLBASEIPI, VLTOTAL, VLREDICMS, FLRICMS, REBATE, QTINDICE, PESOLIQ, VLBASEICMSSUB, VLISS, CODAWBDET, CODAWB, CODCOURIER, AEROORIG, AERODEST, DTDARF, DTEXP, FLSPC, VLII, CODSEGURADORA, NUMPEDCLI, CODMODAL, VLVDLIQ, CODNATOPCLI, FLINTEGRACAO, DIGCONTRAFIN, CODDEVOL,    HRHORA,           HRDURACAO, CIFFOB, CODFILSOLIC, TPFRETE,  ENDFAT, FLNFMANUAL, CODOCORENT, CODTRANSPRED, NUMCONTRAFIN, VLJUROSFIN, PJUROS,        DTATUEST,     FLATUEST, FLDUPLICATA, VLTOTALIND, SEXO, IDADE, CODFUNC, HRHORAINI, DTLIBPED, FLTPVENDA, CODFILSIMPFAT, TPNOTASIMPFAT, NUMNOTASIMPFAT, SERIESIMPFAT, CODFILPDV, DTNOTAPDV, FLNOTAPDV, NUMNOTAPDV, NUMPDV, SERIEPDV, TPNOTAPDV, CONTROLE,     NOME,                     CODCLIENT, ENDCLIENT, CODUSER,       VLAGREGACRC, VLISENTOIPI, VLOUTRASIPI, QTPRC,  VLPRC,  QTVOLUME, FLFISCAL, OBSFISCAL, DTVALID, FLREPLICA,  IDENTPROC,  CODNATOPDIF, CODNATOPCOMPL, NUMNOTADEBITO, NUMNOTAENT, SERIEENT, FLINSTALATERCEIRO, VLFRETETERCEIRO, FLINTFIN, DTALTERACAO, USERIDALT , VLIRRF, TPCONTRATO, SERIECONTRAFIN, NOMERECEB, DTRECEB, HRRECEB, DTSIMPFAT, VLJUROS, CODCLIPUBLICIDADE, CODENDCLIPUBLICIDADE, NUMCTRLPART, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, NRSERIEECF, VLBASEICMD, VLICMD,  VLPISCOFINSCSLL, FLDEVOL, CODTRANSP2, FLSEGURO, VLDESCNOTA, VLBASEICMORIGREPI, VLICMORIGREPI, VLICMREPI, FLTRANSFANEXOAUT, TPPGTO, INTEGRACRC, CODFILORIG, NUMNOTAORIG, SERIEORIG, TPNOTAORIG, DTNOTAORIG, VLTOTALSIMPFAT, VLICMDESCONTO, TOTCUPOMPROMOCIONAL, VLICMTRANSF, ANOMESAPU, VLTAC, CARENCIA, VLTARBANCARIA, NUMOSMONTAG, STATUSOSMONTAG, VLPISDESCONTO, VLCOFDESCONTO, MODELONF, VLBASEICMSDIFSAI, VLICMDIFSAI, NUMORC, DTPREVRETMET, DTUSEREEMISAO, CODUSEREEMISAO, DTAUTORIZACAONFE, NUMNFE, DIGNFE, STATUSNFE, DTCANCELAMENTONFE, NSU, DTIMPRESSAO, DATENT, ESTADOPLACA, ESTADOPLACACARRETA, PLACACARRETA, PLACAVEIC  ,CODNATOPDIFCOMPL, VLTOTPISRET, VLTOTCSLLRET, VLTOTIRRET, VLTOTCOFINSRET, VLNTRIBUTD, VLICMRETV , VLICMCREDITO, VLIBPT, ALIQIBPT,     DATAHORAUTC,    FLMOTORDEPROMOCOES, CODOPER, CHAVEIBPT, FONTEIBPT, ALIQIBPTEST, VLIBPTEST, ALIQIBPTMUN, VLIBPTMUN,                 CHAVENFE,                               CODMODELOSEFAZENTNFE, CODFILDESTENTNFE, CODREMETENTNFE, SERIEENTNFE, DTNOTAENTNFE, NUMNOTAENTNFE, CHAVENFEENTNFE, SEQINVDATA, VLFECEP, VLFECEPST, VLICMPARTUF, VLICMPART, CODCONTR,   CHAVENFEREF,NRSERIEECFREF, FLUTILSAIDA, VLICMSDESON, CODFORNEINTERMEDIADOR, FLPAGINTERMEDIADOR, CODPROFISSAOCASHBACK, VLBASECBS,   VLCBS,      VLBASEIBS,     VLIBS,         VLBASEIBSMUN,                   VLIBSMUN,     VLBASEIS,      VLIS, PERCREDUTOR , tpajuste, FLEXCFCPBCPISCOFINS, FLEXCICMSBCPISCOFINS, NUMCOO, NUMCCF)
     VALUES (         @codfil, @tpnota, @numnota, @serie,  @dtnota,  1,  NULL,   @dtemissao,  @dtpedido,  NULL,  @dtentrega,  @condpgto,  @estado, NULL, NULL,   NULL,    @numpedven, @codcli_gemco,  @codvendr,  @numcxa,   0,    0,    NULL,  NULL,  @endcob,  @endent,   NULL,   1,    0, null, @peso, @praca,  0,   NULL,   NULL,  NULL,  NULL,  '0',    NULL, @obs,   0,     NULL,    @vlbaseicm,     @vldesconto,      0,    NULL,   @vlfrete,  @vlicm,  @vlicmret,  0,   @vlmercad, 0,      0,  @vlentrada,    NULL,    .01,  2,     0,   @codfil,     0,   NULL,  0,   @vloutras, NULL,  NULL,  NULL,   0,   @vltotal,  NULL,   NULL,  NULL,  NULL,  @peso, @vlbaseicmssub, 0,   NULL,   NULL,   NULL,   NULL,   NULL,  NULL,  NULL, NULL, NULL,    0,      NULL,   NULL,   0,     NULL,    NULL,      0,     NULL,   @hrhora ,      NULL,     NULL,  NULL,   3,  @endfat,   'N',     0,    NULL,      0,      0,      0,     @hrhora,     'S',   NULL,    NULL,   NULL, NULL,  0,     NULL,  NULL,    NULL,     0,       0,      0,       NULL,    NULL,    NULL,   NULL,   NULL,   NULL,   NULL,   NULL,  'AC12',  @cliente,             0,    NULL,  @coduser,    0,       0,      0,  @qtprc, @vlprc,   0,    NULL,   NULL,   NULL,   NULL,  @identproc, @codnatop,    NULL,     NULL,     0,    NULL,      NULL,        0,      NULL,   NULL,    NULL,   0,    'C',     '0',     NULL,   NULL,   NULL,  NULL,    0,       0,         0,        NULL,       0,        0,       NULL,  @vlbaseicmd , @vlicmd,  0,       'N',   0,     'N',    0,        0,       0,      0,      NULL,     1,    'N',     0,     0,      NULL,    0,    NULL,     0,       0,       0,          0,    0,    0,    0,      0,     NULL,     NULL,      0,       0,   @modelonf,    0,        0,    0,    NULL,     NULL,      NULL,      NULL, @numnfe_s29, @dignfe_s29,  @statusnfe,      NULL,    NULL,  NULL,  @dtnota ,   NULL,      NULL,       NULL,    NULL,  @codnatopdifcompl,   0,      0,      0,      0,      0,     0,      0,   NULL,  NULL,    @DATAHORAUTC ,    NULL,      0,    NULL,   NULL,    NULL,   NULL,   NULL,    NULL,     @chave,                   NULL,         NULL,       NULL,    NULL,     NULL,    NULL,       NULL,    0,     0,    0,     0,     0,      2,      NULL,    NULL,     NULL,    NULL,      NULL,         NULL,        0,      @vlbasecbs, @vlcbs,  @vlbaseibs,   @vlibs,    @vlbaseibsmun,     @vlibsmun,    0,     0,    0 ,    'F'    , 'N',           'S'    , @numcoo_s29, 0)


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

SELECT o.name, o.modify_date,
       CASE WHEN o.name = 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA'
            THEN CASE WHEN CHARINDEX('script 29', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script29
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA', 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_SCRIPT29')
 ORDER BY o.name;
GO
