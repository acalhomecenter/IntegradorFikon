/*
  27 - Cancelamento FIKON: lançamento de caixa do cupom cancelado (CXA_LANCTO STATUS 9)  -  19/11/2026
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  A procedure completa abaixo já inclui os ajustes dos scripts 20 e 23.
  IMPORTANTE: rodar ANTES de publicar a ApiAcal que grava e cancela a venda com nota já cancelada na FIKON.

  Problema:
    No cancelamento do próprio Gemco, o lançamento de caixa do cupom fica com STATUS 9 (conferido nos 16 cupons
    cancelados da DM desde junho). A SP_FIKON_CANCELAR_NOTA cancelava a nota, os itens e o estoque, mas deixava o
    lançamento ativo: o caixa continuava somando a venda cancelada (ex.: NFC-e 3 U05, 3 U06 e 4 U05 da DM, 18/11).
    A ApiAcal nova grava a venda cuja nota já veio cancelada da FIKON e cancela em seguida; sem este ajuste, o
    lançamento dela também ficaria ativo.

  O que muda (procedure completa abaixo):
    - Cupom (venda de PDV, NUMPED 999999): ao cancelar, os lançamentos da CXA_LANCTO daquela nota
      (filial, tipo, número, série, data) passam para STATUS 9. Nota de pedido (NF-e) não muda.
    - O trigger de UPDATE da CXA_LANCTO só recalcula a flag FLVALIDAPAFECF.
  Os lançamentos já gravados são corrigidos no script 28 (só produção).

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
    - O bloco 1 confere a versão da procedure e guarda a cópia SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT27.
  Para voltar atrás: abrir a cópia _BKP_SCRIPT27, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA'));
DECLARE @h varbinary(32) = HASHBYTES('SHA2_256', @def);

-- aceita: versão com o script 23 (1CB9D4C3...), com o 20 (2125BB85...), do 16 (35217748...) ou já com o 27
IF @def IS NULL
   OR (@h NOT IN (0x1CB9D4C38F9C0995AF46E6EC94675ECF1DCF457B3362BAF56679155B3F78F77B,
                  0x2125BB854F4885B0D61F829C3433B1A7FD04193B86C666775601C69F229F856E,
                  0x35217748E0B0BA22DE2727187BC0D3B79E783F30F19CA8E2808F1507FB05230B)
       AND CHARINDEX(N'script 27', @def) = 0)
BEGIN
    RAISERROR('Nada foi alterado: SP_FIKON_CANCELAR_NOTA nao existe ou esta numa versao diferente da esperada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT27') IS NULL
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_CANCELAR_NOTA]', N'[dbo].[SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT27]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT27') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copia guardada: SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT27.';
END
GO

/* ===================== 2. SP_FIKON_CANCELAR_NOTA (completa) ===================== */
ALTER proc [dbo].[SP_FIKON_CANCELAR_NOTA]  
@chave varchar(44),
@dtcancelamento date,
@horacancelamento time

as

-- script 20 (18/11/2026): a conferencia do cabecalho CAN passa a olhar a data (DTNOTA faz parte da PK da
-- ENT_NOTA). Antes, um CAN antigo com o mesmo numero (ex.: filial 15, CAN 3 de 2021) fazia a proc pular o
-- cabecalho e o item de hoje quebrava na FK ENT_ITENT_FK_NOTA. O cancelamento da MOV_SAIDA e o jornal passam a
-- rodar sempre (antes so rodavam quando o cabecalho era gravado).
-- script 23 (18/11/2026): dois cancelamentos com o mesmo numero no mesmo dia (ex.: DM, NFC-e 3 U05 e 3 U06)
-- usam o mesmo CAN do dia: o valor e somado no cabecalho e o item vai com o proximo ITEM livre quando o
-- produto/item ja existe nesse CAN (antes dava PK duplicada na ENT_ITENT).
-- script 27 (19/11/2026): cupom (venda de PDV, NUMPED 999999) cancelado tem o lancamento de caixa (CXA_LANCTO)
-- marcado com STATUS 9, como no cancelamento do proprio Gemco. Antes o lancamento ficava ativo.

BEGIN TRY 
   begin tran

declare @codfil int

declare @numpedven numeric(12)
declare @numnota numeric(12)
declare @dtnota date
declare @tpnota varchar(3)
declare @serie varchar(3)
declare @vltotal numeric(15,2)
declare @filped int

declare @tpdep varchar(1) 
declare @fisico numeric(12,2)
declare @resfis numeric(12,2)
declare @DATAHORAUTC varchar(50) = FORMAT(SYSDATETIMEOFFSET(), 'yyyy-MM-ddTHH:mm:sszzz');
declare @data date = getdate()
declare @local int

declare @coditprod varchar(9)
declare @qtcomp numeric(12,3)   -- script 16: era numeric(12,2) e cortava a 3a casa (item fracionado)
declare @codembal numeric(4,0)  -- script 16: embalagem do item vendido
declare @codprod numeric(9)
declare @item int
declare @precounit numeric(15,2)
declare @vltotItem numeric(15,2)
declare @conversao numeric(15,2)

declare @totestoque numeric(15,2)

declare @cmup numeric(15,4)
declare @cue numeric(15,4)

declare @seqjornal numeric(12)
declare @itement int   -- script 23: ITEM do item no CAN do dia


if(@codfil in (5,8))
begin
set @tpdep = 'D'
set @local = 2
end
   else
begin
   set @tpdep ='L'
   set @local = 1
end
 
DECLARE CR_CONSULTA CURSOR LOCAL FOR
SELECT
    CODFIL, NUMPEDVEN, NUMNOTA, DTNOTA,
    TPNOTA, SERIE, VLTOTAL, FILPED
FROM MOV_SAIDA
WHERE CHAVENFE = @chave
  AND STATUS <> 9;

OPEN CR_CONSULTA;

FETCH NEXT FROM CR_CONSULTA INTO
    @codfil, @numpedven, @numnota, @dtnota,
    @tpnota, @serie, @vltotal, @filped;

-- Verifica se o cursor encontrou algum registro
IF @@FETCH_STATUS <> 0
BEGIN

    CLOSE CR_CONSULTA;
    DEALLOCATE CR_CONSULTA;

    THROW 50001,
        'Nota fiscal não encontrada ou já cancelada.',
        1;

END;

WHILE @@FETCH_STATUS = 0
BEGIN
   

				-- consulta se ja existe uma entrada
                if(SELECT COUNT(*)  FROM ENT_NOTA  WHERE  CODFIL =  @codfil AND  TPNOTA =  12 AND  CODREMET =  @codfil AND  SERIE =  'CAN' AND  NUMNOTA =  @numnota AND DTNOTA = @data and STATUS<> 9)> 0
				begin

				-- script 23: CAN do dia ja existe (outra venda com o mesmo numero): soma o valor desta venda
				UPDATE ENT_NOTA WITH (READCOMMITTED)
				   SET VLMERCAD = ISNULL(VLMERCAD, 0) + @vltotal, VLOUTRAS = ISNULL(VLOUTRAS, 0) + @vltotal, VLTOTAL = ISNULL(VLTOTAL, 0) + @vltotal
				 WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = @numnota AND DTNOTA = @data AND STATUS <> 9

				end
				  
				  else

				  begin
				   					-- insert ent_nota
										INSERT  INTO ENT_NOTA( CODFIL, TPNOTA, CODREMET, SERIE, NUMNOTA, DTEMISSAO, DTNOTA, DTPEDIDO, DTCANCEL, DTENTREGA, ESTADO, GUIA, ALIQICM, CODNATOP, CODTRANSP, NFCONHEC, CODMENSAG, PESO, SITUACAO, FLEMISSAO, VLDESPACES, VLACRESCIM, VLBASEICMS, VLDESCONTO, VLDESPFIN, VLDESPICM, VLFRETE, VLICM, VLICMRET, VLIPI, VLMERCAD, VLOUTDESP, VLSEGURO, STATUS, PDESC1, PDESC2, PDESC3, PDESC4, PDESC5, PDESC6, CODFILSAI, NUMNOTASAI, VLISENTO, VLOUTRAS, FILPEDSAI, CONDPGTOSAI, DATCOT, LOTCOT, NUMLAN, VLBASEIPI, SERIESAI, PLACAVEIC, ORDEMCHEG, VLBASEICMSSUB, VLTOTAL, PDESCDUP, VLDESCDUP, DTATUEST,       FLATUEST, ENDENT, OBS, CODFILSIMPFAT, TPNOTASIMPFAT, NUMNOTASIMPFAT, SERIESIMPFAT, CODREMETSIMPFAT, CODSITTITCPG, CODUSER, CODFUNCCONF, CODFUNCDESC, HRFIMDESC, HRINIDESC, VLDESCARGA, VLISENTOIPI, VLOUTRASIPI, NUMDOCTO, PDESCICMS, VLIMPIMPORT, FLFISCAL, OBSFISCAL, FLINTEGRACPG, FLREPLICA, DTNOTASAI, TPNOTASAI, CONTROLE, PDESCESP, PFATURA, CODDEVOL, DESCREMETENTE, CODNATOPCOMPL, CODNATOPDIF, CODNATOPDIFCOMPL, FLCIFFOB, NUMPORTARIA, VLIRRF, CODCONTACOB, CODTPCOB, NUMAGECOB, NUMAGEDEST, NUMBCOCOB, NUMBCODEST, NUMCTACOB, NUMCTADEST, VLISS, VLBASEISS, VLBASEIRRF, ALIQISS, ALIQIRRF, SERIECONTRAFIN, TPCONTRATO, NUMCONTRAFIN, CODEMPR, TPNEG, CODRETIMPRENDA, DIGAGECOB, DIGAGEDEST, DIGCONTACOB, DIGCONTADEST, ANOPORTARIA, CODDOCA, PLACACARRETA, NUMPF, VLFUNRURAL,          IDENTPROC,                       DTALTERACAO, USERIDALT, FLTPNFDEVOL, PESOLIQ, PDESCFIN, CODVENDR, ALIQINSS, VLBASEINSS, VLINSS, FLENDERENTRADA, NRDIASATRASO, VLSUFRAMA, FLCONTRANF, NUMCONTRANF, VLBASEICMSSUBC, VLICMRETC, QTRECDEVIMP, VLICMSANTEC, NUMCTRLPART, PERCDESCPRESUMIDOF, PERCDESCPRESUMIDOV, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, NUMDAR, VLICMSGARANTIDO, VLBASEICMD, VLICMD, FLSEMSERIE, VLCOFSUB, VLPISSUB, VLCDO, CODAUTORIZACAO, ALIQCSLL, VLCSLL, VLBASECSLL, ALIQCOFINSRET, ALIQPISRET, VLBASECOFINSRET, VLBASEPISRET, VLCOFINSRET, VLPISRET, FLSSCC, VLJUROSFIN, VLJUROS, FLINTCONF, VLICMORIGREPI, VLBASEICMORIGREPI, VLICMREPI, VLICMSGARANTIDODAR, DTREFERDAR, DTVENCDAR, TPPGTO, VLBASEICMDIF, VLICMDIF, CODFILORIG, CODREMETORIG, NUMNOTAORIG, SERIEORIG, CODCLASCONSENERELE, CODUNICONENERELE, DEMANDAENERELEFORA, DEMANDAENERELEPONTA, DTFIMCONENERELE, DTINICONENERELE, NUMCONSUMIDORESENERELE, KWH, VLICMDESCONTO, VLDESCNOTA, VLICMTRANSF, ANOMESAPU, VLBASEICMEG, VLICMEG, FLGERARF, VLPISDESCONTO, VLCOFDESCONTO, VLICMCREDITO, VLPIN, MODELONF, DTPREVRETMDT, OBSNFE, VLICMCONHECSUB, VLBASEICMSGARANTIDO, VLBASEICMDIFANTEC, VLICMDIFANTEC, NUMORCDESP, TPVERBA, VLPINDAR,      DTAUTORIZACAONFE,        NUMNFE, DIGNFE, STATUSNFE, DTCANCELAMENTONFE, STATUSANT, CODFORNECOLIGADO, ICMPRESUMIDO, CODFILCOMPLORIG, CODREMETCOMPLORIG, TPNOTACOMPLORIG, NFCOMPLORIGINAL, SERIECOMPLORIG, NSU, DTIMPRESSAO, FLSEGURO, FLCONTINGENCIA, FLNFE, VERSAONFE, VLBASEICMSANTEC, CHAVENFE, FLDTVENCTOCPGCONFNF, VLNTRIBUTD, VLICMRETV, FLUTILNOTA, DATAHORAUTC, VLICMRETSIMPFAT, SEQINVDATA, VLFECEP, VLFECEPST, VLICMPARTUF, VLICMPART, CODCONTR, FLCONFPORTARIA, DTCONFPORTARIA, NRSERIEECFREF, NUMNOTAREF, DTNOTAREF, SERIEREF, MODELONFREF, CODFILREF, DTSIMPFAT, NUMNOTANFSE, CODVERIFICACAONFSE, VLICMSDESON, VLFECEPSTGARANTIDO, CODMUNIBGEORIG, ESTTRAJETOORIG, CIDTRAJETOORIG, CODMUNIBGEDEST, ESTTRAJETODEST, CIDTRAJETODEST, QTVOLUME, FLEXCICMSBCPISCOFINS, FLEXCFCPBCPISCOFINS, FLCROSSDOCKINGAUT, FLCONTRIBUINTECPRB, TPSERVICOREINF, OBSREINF, CNPJINTERMEDIADOR, IDENTINTERMEDIADOR, FLMOVENDERECAR, CODFINDOCE, CODTIPFAT, VLBASECBS, VLCBS, VLBASEIBS, VLIBS, VLBASEIBSMUN, VLIBSMUN, VLBASEIS, VLIS ) 
										VALUES ( @codfil, 12, @codfil, 'CAN', @numnota, @data, @data, NULL, NULL, @data,      'CE',   NULL,    0,      10,       NULL,     NULL,      NULL,     0,    NULL,       NULL,       0,           0,         0,          0,           0,       NULL,     0,      0,       0,       0,  @vltotal,    0,          0,      1,     0,       0,       0,     0,     NULL,   NULL,    NULL,       NULL,       0,       @vltotal, NULL,       NULL,      NULL,    NULL,   NULL,    0,         NULL,     NULL,     NULL,          0,       @vltotal,   0,        0,      GETDATE() ,        'S',    NULL,  NULL,     NULL,        NULL,             NULL,         NULL,            NULL,           NULL,     537,      NULL,         NULL,       NULL,       NULL,      NULL,          0,        0,          NULL,      0,          0,        NULL,     NULL,         NULL,        NULL,    NULL,        NULL,    NULL,       0,      NULL,    NULL,         NULL,         0,             0,              0,           NULL,         NULL,  NULL,      NULL,       NULL,      NULL,      NULL,     NULL,       NULL,       NULL,       NULL,    NULL,     NULL,      NULL,     NULL,      NULL,      NULL,          NULL,         NULL,       1,     0,        NULL,          NULL,     NULL,        NULL,         NULL,         NULL,      NULL,     NULL,      NULL,     0,  'CANCELAMENTO REALIZADO VIA INTEGRADOR FIKON', NULL,           NULL,     NULL,         0,       NULL,    NULL,    NULL,       NULL,    NULL,       NULL,             NULL,       NULL,      NULL,       NULL,          NULL,         NULL,      NULL,       NULL,        NULL,            NULL,               NULL,              NULL,               NULL,     NULL,         NULL,           0,       0,      NULL,       NULL,     NULL,   NULL,       NULL,        NULL,    NULL,     NULL,        NULL,         NULL,           NULL,         NULL,         NULL,      NULL,     'N',      NULL,     NULL,    'N',         NULL,            NULL,           NULL,        NULL,              NULL,      NULL,   NULL,        NULL,    NULL,      NULL,          NULL,        NULL,        NULL,          NULL,               NULL,              NULL,              NULL,             NULL,              NULL,              NULL,           NULL,     NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,        @DATAHORAUTC,  0, NULL, 0, 0, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 0, 0)

                             end -- script 20: fim do insert do cabecalho

										-- Update mov_saida
										   UPDATE MOV_SAIDA  WITH (READCOMMITTED) SET   DTCANCEL =  @data , STATUS =  9, statusnfe=9,  NUMORC =  NULL  WHERE 1=1 AND CODFIL =  @codfil AND TPNOTA =  @tpnota AND NUMNOTA =  @numnota AND SERIE =  @serie AND DTNOTA =  @dtnota

										-- script 27: lancamento de caixa do cupom cancelado (como no Gemco: STATUS 9)
										if (@numpedven = 999999)
										   UPDATE CXA_LANCTO WITH (READCOMMITTED) SET STATUS = 9
										    WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND NUMNOT = @numnota AND SERIE = @serie AND DATENT = @dtnota
										      AND NUMPED = 999999 AND TIPOPED = 1 AND STATUS <> 9
				   
										-- insert no jornal
										 exec SP_SEQJORNAL
										 set @seqjornal = ( select LAST_NUMBER from SEQJORNAL  )

										INSERT  INTO MOV_JORNAL( CODFIL, CODMODULO, CODFUNCAO, PRIORIDADE, DATA, HORA, DESCRICAO, OBSERVACAO, ESTACAO, CODUSER, STATUS, REG_ID ) 
										VALUES ( @codfil, 6, 1, 0, CONVERT(VARCHAR,GETDATE(),111), CONVERT(VARCHAR,GETDATE(),108), 'EXCLUSAO DA NOTA FISCAL N.'+ convert(varchar,@numnota), NULL, 'FIKON', 537, 0, @seqjornal) 

									
										


							DECLARE CR_CONSULTA_ITENS CURSOR FOR
							SELECT MOV_ITSAIDA.CODITPROD , MOV_ITSAIDA.ITEM , MOV_ITSAIDA.QTCOMP,
                                   -- script 16: preço, total, conversão e embalagem do item vendido vão para a entrada do cancelamento
                                   MOV_ITSAIDA.PRECOUNIT, MOV_ITSAIDA.VLTOTAL, ISNULL(NULLIF(MOV_ITSAIDA.QTEMB, 0), 1), ISNULL(MOV_ITSAIDA.CODEMBAL, 0)
                              FROM MOV_ITSAIDA   WHERE 1=1 AND  CODFIL =  @codfil AND  TPNOTA =  @tpnota AND  NUMNOTA =  @numnota AND  DTNOTA = @dtnota AND  SERIE = @serie
							OPEN CR_CONSULTA_ITENS
								FETCH NEXT FROM CR_CONSULTA_ITENS INTO @coditprod, @item ,@qtcomp, @precounit, @vltotItem, @conversao, @codembal 
									WHILE @@FETCH_STATUS = 0
										BEGIN
                            
						  set @codprod = (select MAX(codprod) from CAD_ITPROD where CODITPROD = @coditprod)

						--consulta estoque
						  SELECT @FISICO = FISICO, @RESFIS = RESFIS  FROM CAD_PRODLOC  WHERE 1=1 AND CODFIL = @codfil AND TPDEPOS =  @tpdep AND CODITPROD =  @coditprod

						-- da Baixa no estoque
						 exec SPU_PROLOCI 1, @codfil, @tpdep, @coditprod, 0, @qtcomp, 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0 

						 --estoque total
						 SELECT @totestoque = SUM(FISICO + TECNICO + MOSTRUARIO) FROM CAD_ITPROD ITP, CAD_PRODLOC LOC, CAD_FILIAL CF  WHERE 1=1 AND ITP.CODITPROD = LOC.CODITPROD AND LOC.CODFIL = CF.CODFIL AND ITP.CODPROD = @codprod AND CF.CODFILCUST = 8


						 -- insert na mov_extrato
						INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD, FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS, RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC ) 
						VALUES ( @codfil, @numpedven,@numnota, GETDATE(),@tpnota, 'S', 4, @coditprod, @fisico, @resfis, 0, 0, 0, 0, 0, 0, 0,@qtcomp, 'RESFIS;', 'N', @fisico, @resfis+@qtcomp, 0, 0, 0, 0, 0, 0, 0, @codfil, GETDATE(), 'CANCELANOTAFISCAL', '', 'REALIZADO PELO INTEGRADOR FIKON' )


						-- Update mov_saida 
						UPDATE MOV_ITSAIDA  WITH (READCOMMITTED) SET   STATUS =  9,  CODTECNICO =  NULL, NUMORC =  NULL  WHERE 1=1 AND CODFIL =  @codfil AND TPNOTA =  @tpnota AND NUMNOTA =  @numnota AND DTNOTA = @dtnota AND SERIE =  @serie



						-- select custo 
						SELECT @cmup = CMUP , @cue = CUE  FROM VEN_PRODFIL   WHERE 1=1 AND  CODFIL =  8 AND  CODPROD =  @codprod


						  SELECT @FISICO = FISICO, @RESFIS = RESFIS  FROM CAD_PRODLOC  WHERE 1=1 AND CODFIL = @codfil AND TPDEPOS =  @tpdep AND CODITPROD =  @coditprod

						--entrada de estoque
						exec SPU_PROLOCI 1, @codfil, @tpdep, @coditprod, @qtcomp, 0, 0, 0, 0, 0, 0, 0, 0, NULL , 0, @data, @qtcomp, 12, @numnota, 0, 0, 0, 0, 0


						--insere na mov_extrato a entrada
						INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD, FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS, RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC ) 
						VALUES ( @codfil, 0,@numnota, GETDATE(),12, 'E', 5,@coditprod, @fisico, @resfis, 0, 0, 0, 0, 0, 0, 0,@qtcomp, 'FISICO;', 'N', @fisico+@qtcomp, @resfis, 0, 0, 0, 0, 0, 0, 0, @codfil, GETDATE(), 'GRAVAITENSNFENTRADA', '', 'REALIZADO PELO INTEGRADOR FIKON' )

						-- script 23: ITEM livre no CAN do dia (outra venda com o mesmo numero pode ter o mesmo produto/item)
						set @itement = @item
						if exists (SELECT 1 FROM ENT_ITENT WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = @numnota AND DTNOTA = @data AND CODITPROD = @coditprod AND ITEM = @itement)
						   SELECT @itement = ISNULL(MAX(ITEM), 0) + 1 FROM ENT_ITENT WHERE CODFIL = @codfil AND TPNOTA = 12 AND CODREMET = @codfil AND SERIE = 'CAN' AND NUMNOTA = @numnota AND DTNOTA = @data

						-- inserindo itens da entrada
						INSERT  INTO ENT_ITENT(CODFIL, TPNOTA, CODREMET, SERIE, NUMNOTA, CODITPROD, NUMPEDCOMP, ITEM, DTNOTA, FILDEST, PRECOUNIT, ALIQICM, VLIPI, PORCIPI, SITUACAO, QTCOMP, QTRECEB,    QTEMBAL, QTESTOQUE, CUSTANT, CODEMBAL, CODPRODDF, STATUS, CUSTANTI, VLDESCONTO, LOCAL,    VLDESPFIN, VLICM, VLDESPESAS, VLCONHEC, VLICMRET, QTDEVOL, VLISENTO, VLOUTRAS,    QTCONSIG, VLBASEICMS,  VLNTRIBUT, TOTESTOQUE,    CODVENDR, ALIQICMRED, ALIQICMSUB, ALIQICMSUBUF, VLBASEICMSSUB, CONVERSAO, VLICMF, VLICMRETF, VLISENTOF,       VLOUTRASF, VLBASEICMSF, VLNTRIBUTF, VLBASEICMSSUBF, QTSALDO, CODCONJU, DESCCOMPLE, VLICMFRT, VLICMSUBREC, COMPLEMENTO, VLOUTRASIPI, VLBASEIPI, VLISENTOIPI, FLATUALIZAPRECO, CODREMETNF, SERIENF,   CMUP,     ALIQIRF, VLDIVIPI, FLREPLICA, CODITCONJU, QTORIG,  HRHORA,      VLPISSUB, VLCOFSUB, CODBARRA, VLDESPACES,  VLFRETE,  VLDESCITEMRAT, VLISS, VLOUTDESP, VLSEGURO, VLSUPINF, VLTOTITEM,   CTF, VLDESCITEM,    VLTOTAL,    QTRETARMAZEM, VLTOTIPI, VLDESPRAT, DPI, CODNATOP, CODNATOPDIF, CODNATOPCOMPL, CODNATOPDIFCOMPL, QTAVARIA, CONDPGTO, VLFUNRURAL, FLAPURACOMISS, FLDEVOLAUTOM, CUE, OBSFISCAL, VLTOTBASEIPI, ALIQINSS, VLBASEINSS, VLINSS, VLIRRF, CODFILANEXO, CODPALLET, FLCROSSDOCKING, CODPRESTSERV, DESCPRESTSERV, VLBASEICMSSUBC, VLICMRETC, VLJUROSVENDA, VLICMSANTEC, MEDGER, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, VLPIS, VLCOFINS, VLBASEICMD, VLICMD, VLIPIC, VLTOTIPIC, VLICMSGARANTIDO, ALIQCSLL, VLBASECSLL, VLCSLL, VLPIN, PORCIPIENT, VLSUFRAMA, CMUPANT, PPIS, PCONTSOC, PADM, VLICMEG, VLBASEICMEG, VLJUROSFIN, VLJUROS, TABELA, VLICMORIGREPI, VLBASEICMORIGREPI, VLICMREPI, VLFRETETERC, VLICMSFRETETERC, DTVALIDADE, ALIQICMDIF, VLBASEICMDIF, VLICMDIF, VLICMDESCONTOF, VLDESCNOTA, VLPISDESCONTOF, VLCOFDESCONTOF, VLICMCREDITO, ALIQICMCREDITO, CUEPIN, PPIN, TXFUNRURAL, VLBASEPIS, VLBASECOFINS, CODDEVOL, PERCICMREDPISCOFINS, VLBASEICMSGARANTIDO, CUSTOGER,   DTATUEST, ALIQICMDIFANTEC, VLBASEICMDIFANTEC, VLICMDIFANTEC, VLBASEICMSATIVO, ALIQICMSATIVO, VLICMSATIVO, ICMPRESUMIDO, ALIQICMPRES, ICMPRESUMIDOF, CUEI , FLNFCOMPL , ALIQICMREDUF , FLESTOQUE , ALIQICMSGARANTIDO, CSTCOFINS, CSTPIS , ALIQPCTM, VLBASEICMSANTEC, ALIQICMSANTEC, FLREATACBA, VLNTRIBUTD , DESCUNIDTRIBUTAVELNF, FATORCONVTRIBUTAVELNF, VLICMRETV, ORIGEMPROD, ALIQICMCARGALIQST, ALIQFECEP, VLFECEP , VLICMRETSIMPFAT, CUETRANSF, CMUPTRANSF, ALIQICMPART, VLFECEPF, VLFECEPSTF, VLFECEPST, VLICMPARTUFF, VLICMPARTUF, VLICMPARTF, VLICMPART, FLFECEPADIC, CEST , CUETRANSFSAI, CMUPTRANSFSAI, ALIQICMUF, CSTIPI, CODIGO53, CODIGO511, VLAJUSTEITEM, ALIQFECEPST, VLBASEFECEPSTF, VLBASEFECEPF, VLBASEICMPARTUFF , CODIGO52, CODIGO56, VLBASESTRETANT, VLICMSTRETANT, ALIQICMSTRETANT, VLBASEFCPSTRETANT, ALIQFCPSTRETANT, VLFCPSTRETANT, FLPAUTAPRECO, VLBASEICMSEFETIVO, VLICMSEFETIVO , ALIQFEEFMT, VLBASEFEEFMT, VLFEEFMT, VLFEEFMTF, VLSUBSTITUTOSTRETANT , VLICMSDESON, CODMOTDESICMS, VLICMOPERACAO, ALIQICMDIFERIMENTO, VLICMDIFERIDO, VLFECEPSTGARANTIDO, VLICMOPERSTF, VLFECEPOPERSTF, VLNTRIBUTUF , VLDESCBASEPIS, VLDESCBASECOFINS, DESCRPRODNFE, CUSTORE, CUE_RE6763, CMUP_RE6763, CODITPRODABENEF , CLASTRIBCBS , CLASTRIBIBS, CLASTRIBIS, CSTCBS, CSTIBS, CSTIS , VLBASECBS, ALIQCBS, VLCBS, VLBASEIBS, ALIQIBS, VLIBS, VLBASEIBSMUN, ALIQIBSMUN, VLIBSMUN, VLBASEIS, ALIQIS, VLIS) 
						VALUES ( @codfil, 12, @codfil, 'CAN', @numnota, @coditprod, NULL, @itement, @data, NULL, @precounit, 0, 0, 0, NULL,                                             @qtcomp,    @qtcomp, NULL,    @fisico,   NULL,      @codembal,       NULL,      1,       NULL,       0,    @local,        NULL,    0,      NULL,        0,        0,        0,        0,   @vltotItem,    NULL,        0,          0,        @totestoque,  NULL,        0,          0,           0,            0,       @conversao,        0,       0,           0,   CASE WHEN @qtcomp <> 0 THEN ROUND(@vltotItem / @qtcomp, 4) ELSE 0 END,       0,          0,             0,         0,        NULL,     NULL,       0,         0,          NULL,        0,            0,          0,           NULL,          0,       NULL,    @cmup,        0,       NULL,     NULL,      NULL,       0, {FN CURTIME()},    0,        0,       NULL,       0,        NULL,         0,          0,      0,          0,       0,       @vltotItem, 0,       0,       @vltotItem,        0,          0,        0,      0,      10,       NULL,          0,              NULL,        NULL,      NULL,      0,           NULL,        NULL,      @cue,  NULL,          0,         NULL,      NULL,    NULL,   NULL,     NULL,        NULL,        NULL,             0,           NULL,            0,         0,             NULL,       NULL,    NULL,        NULL,             NULL,        NULL,    NULL,       0,         0,   NULL,     NULL,          NULL,        NULL,      NULL,     NULL,  NULL,     NULL,      NULL,     NULL,    0,       0,    NULL, NULL,        NULL,       NULL,    NULL,      0,         NULL,           NULL,           NULL,      NULL,            NULL,       NULL,        NULL,        NULL,      NULL,         NULL,         NULL,        NULL,           NULL,             NULL,       NULL,       NULL,   NULL,    NULL,      NULL,       NULL,         NULL,             NULL,               NULL,       NULL,     GETDATE(),        NULL,          NULL,                NULL,         NULL,           NULL,        NULL,         NULL,         NULL,          NULL,   NULL,'N',          NULL,         NULL,            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 'N', NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 0, 0, 0, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)



						--update mov_itped
						UPDATE MOV_ITPED  WITH (READCOMMITTED) SET   STATUS =  5, SITCARGA =  0, QTFAT =  QTFAT - @Qtcomp, QTLIB =  QTLIB + @qtcomp  WHERE 1=1 AND CODFIL =  @filped AND TIPOPED =  0 AND NUMPEDVEN =  @numpedven AND CODITPROD =  @coditprod AND ITEM =  @item AND FILORIG=@codfil and NUMPEDVEN <> 999999

						-- update demais itens
						UPDATE MOV_ITPED  WITH (READCOMMITTED) SET   STATUS =  8  WHERE 1=1 AND CODFIL =  @filped  AND NUMPEDVEN =  @numpedven AND CODITPROD =  @coditprod AND ITEM =  @item AND QTFAT>0 and NUMPEDVEN <> 999999

						

			        FETCH NEXT FROM CR_CONSULTA_ITENS INTO
                @coditprod,
                @item,
                @qtcomp, @precounit, @vltotItem, @conversao, @codembal;

        END; -- Fecha WHILE CR_CONSULTA_ITENS

        CLOSE CR_CONSULTA_ITENS;
        DEALLOCATE CR_CONSULTA_ITENS;

        FETCH NEXT FROM CR_CONSULTA INTO
            @codfil,
            @numpedven,
            @numnota,
            @dtnota,
            @tpnota,
            @serie,
            @vltotal,
            @filped;

    END; -- Fecha WHILE CR_CONSULTA

    CLOSE CR_CONSULTA;
    DEALLOCATE CR_CONSULTA;


		--vefifica status dos itens
						               if( SELECT COUNT(*)  FROM MOV_ITPED   WHERE 1=1 AND CODFIL = @filped AND TIPOPED = 0 AND NUMPEDVEN = @numpedven AND (STATUS = 6 OR STATUS = 8) and NUMPEDVEN <> 999999) > 0
									     begin
										      --update mov_pedido
										UPDATE MOV_PEDIDO  WITH (READCOMMITTED) SET   SITCARGA =  0, STATUS =  8, FLBXESTOQUE =  NULL  WHERE 1=1 AND CODFIL =  @filped  AND NUMPEDVEN =  @numpedven and NUMPEDVEN <> 999999
										update FIKON_INTEGRACAO_PEDIDO set status='FATURADO PARCIAL'where  pedido_gemco =  @numpedven  
										 end
										   else
										     begin
											  --update mov_pedido
										        UPDATE MOV_PEDIDO  WITH (READCOMMITTED) SET   SITCARGA =  0, STATUS =  5, FLBXESTOQUE =  NULL  WHERE 1=1 AND CODFIL =  @filped  AND NUMPEDVEN =  @numpedven and NUMPEDVEN <> 999999
												update FIKON_INTEGRACAO_PEDIDO set status='LIBERADO CXA'where  pedido_gemco =  @numpedven 
											 end


END TRY

BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    DECLARE @Mensagem NVARCHAR(2048);

    SET @Mensagem =
        'Erro ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) +
        ' na linha ' + CAST(ERROR_LINE() AS VARCHAR(10)) +
        ': ' + ERROR_MESSAGE();

    THROW 50000, @Mensagem, 1;

END CATCH;

  commit
GO

SET NOEXEC OFF;
GO

SELECT o.name, o.modify_date,
       CASE WHEN o.name = 'SP_FIKON_CANCELAR_NOTA'
            THEN CASE WHEN CHARINDEX('script 20', OBJECT_DEFINITION(o.object_id)) > 0
                       AND CHARINDEX('script 23', OBJECT_DEFINITION(o.object_id)) > 0
                       AND CHARINDEX('script 27', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajustes_20_23_27
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_CANCELAR_NOTA', 'SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT27')
 ORDER BY o.name;
GO
