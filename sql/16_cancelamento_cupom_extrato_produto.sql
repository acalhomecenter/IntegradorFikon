/*
  16 - Cancelamento e cupom FIKON: extrato de produtos com quantidade 0  -  16/11/2026
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  As duas procedures estão iguais nas duas bases (conferido por hash SHA-256); o script confere de novo.

  Problema (produto 722575 na filial 502, 16/11/2026, tela Extrato/Movimentação de Produtos):
    - a linha do cancelamento da nota 117 (série CAN) aparece com quantidade 0 e o saldo não volta;
    - a venda do cupom 118 aparece com quantidade 0.
  O estoque (CAD_PRODLOC) está certo; quem está errado são os itens gravados pela integração:
    - ENT_ITENT do cancelamento com CONVERSAO, PRECOUNIT, VLTOTAL e VLTOTITEM nulos (nos 2.629 cancelamentos
      nativos desde agosto a CONVERSAO nunca é nula);
    - MOV_ITSAIDA do cupom com QTEMB nulo (nos 40.447 itens nativos desde outubro nunca é nulo).

  O que muda:
    SP_FIKON_CANCELAR_NOTA (procedure completa abaixo):
      1. O cursor dos itens passa a trazer da venda o PRECOUNIT, o VLTOTAL, a embalagem (QTEMB -> CONVERSAO) e o
         CODEMBAL. Antes @precounit, @vltotItem e @conversao eram declaradas e nunca preenchidas.
      2. ENT_ITENT: CODEMBAL do item vendido (antes 0 fixo); VLOUTRASF unitário (antes recebia o total).
      3. @qtcomp com 3 casas (antes numeric(12,2) cortava item fracionado, ex.: 0,708).
      4. Extrato de estoque (MOV_EXTRATOPROD): filial e data reais (antes CODFILLOG 8 e DTPROC '08/18/2026'
         fixos); na entrada, quantidade real (antes 1 fixo) e reserva sem mudança (antes somava a quantidade).
    SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA (procedure completa abaixo):
      5. QTEMB do item = CAD_EMBAL.QTEMB da embalagem 0 do produto (antes ficava NULL).

  Não muda: os dois registros já gravados (cancelamento 117 e cupom 118 da filial 502). Os triggers de UPDATE
  da ENT_ITENT e da MOV_ITSAIDA reprocessam a linha; corrigir esses dois exige análise à parte.

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
    - O 1º bloco confere a versão das procedures e guarda cópias <nome>_BKP_SCRIPT16. Se algo estiver
      diferente, o script para (SET NOEXEC ON) e nada é alterado.
  Para voltar atrás: abrir a <nome>_BKP_SCRIPT16, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @erro varchar(1000) = '';
DECLARE @def nvarchar(max);

-- SP_FIKON_CANCELAR_NOTA: versão atual (SHA-256 2567815DBBB1E399...) ou já com o script 16
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_CANCELAR_NOTA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0x2567815DBBB1E399ABE74848AE0BB83F53A200F0227D672272C6FDD4CB44A11A AND CHARINDEX(N'script 16', @def) = 0
    SET @erro = @erro + 'SP_FIKON_CANCELAR_NOTA esta numa versao diferente da esperada. ';

-- SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: versão atual (SHA-256 7C0602BB34F2878E...) ou já com o script 16
SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA'));
IF @def IS NULL
    SET @erro = @erro + 'SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) <> 0x7C0602BB34F2878E016419062CE16BAD88BFF6BFEE1718A91D533BF5230DB263 AND CHARINDEX(N'script 16', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA esta numa versao diferente da esperada. ';

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT16') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA')), N'[dbo].[SP_FIKON_CANCELAR_NOTA]', N'[dbo].[SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT16]');
        EXEC sys.sp_executesql @def;
    END
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT16') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA')), N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]', N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT16]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT16') IS NULL
       OR OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT16') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar as copias de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copias guardadas: <nome>_BKP_SCRIPT16.';
END
GO

/* ===================== 2. SP_FIKON_CANCELAR_NOTA (completa) ===================== */


ALTER proc [dbo].[SP_FIKON_CANCELAR_NOTA]  
@chave varchar(44),
@dtcancelamento date,
@horacancelamento time

as

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
                if(SELECT COUNT(*)  FROM ENT_NOTA  WHERE  CODFIL =  @codfil AND  TPNOTA =  12 AND  CODREMET =  @codfil AND  SERIE =  'CAN' AND  NUMNOTA =  @numnota and STATUS<> 9)> 0
				begin

				select 'Já Existe uma nota de entrada'

				end
				  
				  else

				  begin
				   					-- insert ent_nota
										INSERT  INTO ENT_NOTA( CODFIL, TPNOTA, CODREMET, SERIE, NUMNOTA, DTEMISSAO, DTNOTA, DTPEDIDO, DTCANCEL, DTENTREGA, ESTADO, GUIA, ALIQICM, CODNATOP, CODTRANSP, NFCONHEC, CODMENSAG, PESO, SITUACAO, FLEMISSAO, VLDESPACES, VLACRESCIM, VLBASEICMS, VLDESCONTO, VLDESPFIN, VLDESPICM, VLFRETE, VLICM, VLICMRET, VLIPI, VLMERCAD, VLOUTDESP, VLSEGURO, STATUS, PDESC1, PDESC2, PDESC3, PDESC4, PDESC5, PDESC6, CODFILSAI, NUMNOTASAI, VLISENTO, VLOUTRAS, FILPEDSAI, CONDPGTOSAI, DATCOT, LOTCOT, NUMLAN, VLBASEIPI, SERIESAI, PLACAVEIC, ORDEMCHEG, VLBASEICMSSUB, VLTOTAL, PDESCDUP, VLDESCDUP, DTATUEST,       FLATUEST, ENDENT, OBS, CODFILSIMPFAT, TPNOTASIMPFAT, NUMNOTASIMPFAT, SERIESIMPFAT, CODREMETSIMPFAT, CODSITTITCPG, CODUSER, CODFUNCCONF, CODFUNCDESC, HRFIMDESC, HRINIDESC, VLDESCARGA, VLISENTOIPI, VLOUTRASIPI, NUMDOCTO, PDESCICMS, VLIMPIMPORT, FLFISCAL, OBSFISCAL, FLINTEGRACPG, FLREPLICA, DTNOTASAI, TPNOTASAI, CONTROLE, PDESCESP, PFATURA, CODDEVOL, DESCREMETENTE, CODNATOPCOMPL, CODNATOPDIF, CODNATOPDIFCOMPL, FLCIFFOB, NUMPORTARIA, VLIRRF, CODCONTACOB, CODTPCOB, NUMAGECOB, NUMAGEDEST, NUMBCOCOB, NUMBCODEST, NUMCTACOB, NUMCTADEST, VLISS, VLBASEISS, VLBASEIRRF, ALIQISS, ALIQIRRF, SERIECONTRAFIN, TPCONTRATO, NUMCONTRAFIN, CODEMPR, TPNEG, CODRETIMPRENDA, DIGAGECOB, DIGAGEDEST, DIGCONTACOB, DIGCONTADEST, ANOPORTARIA, CODDOCA, PLACACARRETA, NUMPF, VLFUNRURAL,          IDENTPROC,                       DTALTERACAO, USERIDALT, FLTPNFDEVOL, PESOLIQ, PDESCFIN, CODVENDR, ALIQINSS, VLBASEINSS, VLINSS, FLENDERENTRADA, NRDIASATRASO, VLSUFRAMA, FLCONTRANF, NUMCONTRANF, VLBASEICMSSUBC, VLICMRETC, QTRECDEVIMP, VLICMSANTEC, NUMCTRLPART, PERCDESCPRESUMIDOF, PERCDESCPRESUMIDOV, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, NUMDAR, VLICMSGARANTIDO, VLBASEICMD, VLICMD, FLSEMSERIE, VLCOFSUB, VLPISSUB, VLCDO, CODAUTORIZACAO, ALIQCSLL, VLCSLL, VLBASECSLL, ALIQCOFINSRET, ALIQPISRET, VLBASECOFINSRET, VLBASEPISRET, VLCOFINSRET, VLPISRET, FLSSCC, VLJUROSFIN, VLJUROS, FLINTCONF, VLICMORIGREPI, VLBASEICMORIGREPI, VLICMREPI, VLICMSGARANTIDODAR, DTREFERDAR, DTVENCDAR, TPPGTO, VLBASEICMDIF, VLICMDIF, CODFILORIG, CODREMETORIG, NUMNOTAORIG, SERIEORIG, CODCLASCONSENERELE, CODUNICONENERELE, DEMANDAENERELEFORA, DEMANDAENERELEPONTA, DTFIMCONENERELE, DTINICONENERELE, NUMCONSUMIDORESENERELE, KWH, VLICMDESCONTO, VLDESCNOTA, VLICMTRANSF, ANOMESAPU, VLBASEICMEG, VLICMEG, FLGERARF, VLPISDESCONTO, VLCOFDESCONTO, VLICMCREDITO, VLPIN, MODELONF, DTPREVRETMDT, OBSNFE, VLICMCONHECSUB, VLBASEICMSGARANTIDO, VLBASEICMDIFANTEC, VLICMDIFANTEC, NUMORCDESP, TPVERBA, VLPINDAR,      DTAUTORIZACAONFE,        NUMNFE, DIGNFE, STATUSNFE, DTCANCELAMENTONFE, STATUSANT, CODFORNECOLIGADO, ICMPRESUMIDO, CODFILCOMPLORIG, CODREMETCOMPLORIG, TPNOTACOMPLORIG, NFCOMPLORIGINAL, SERIECOMPLORIG, NSU, DTIMPRESSAO, FLSEGURO, FLCONTINGENCIA, FLNFE, VERSAONFE, VLBASEICMSANTEC, CHAVENFE, FLDTVENCTOCPGCONFNF, VLNTRIBUTD, VLICMRETV, FLUTILNOTA, DATAHORAUTC, VLICMRETSIMPFAT, SEQINVDATA, VLFECEP, VLFECEPST, VLICMPARTUF, VLICMPART, CODCONTR, FLCONFPORTARIA, DTCONFPORTARIA, NRSERIEECFREF, NUMNOTAREF, DTNOTAREF, SERIEREF, MODELONFREF, CODFILREF, DTSIMPFAT, NUMNOTANFSE, CODVERIFICACAONFSE, VLICMSDESON, VLFECEPSTGARANTIDO, CODMUNIBGEORIG, ESTTRAJETOORIG, CIDTRAJETOORIG, CODMUNIBGEDEST, ESTTRAJETODEST, CIDTRAJETODEST, QTVOLUME, FLEXCICMSBCPISCOFINS, FLEXCFCPBCPISCOFINS, FLCROSSDOCKINGAUT, FLCONTRIBUINTECPRB, TPSERVICOREINF, OBSREINF, CNPJINTERMEDIADOR, IDENTINTERMEDIADOR, FLMOVENDERECAR, CODFINDOCE, CODTIPFAT, VLBASECBS, VLCBS, VLBASEIBS, VLIBS, VLBASEIBSMUN, VLIBSMUN, VLBASEIS, VLIS ) 
										VALUES ( @codfil, 12, @codfil, 'CAN', @numnota, @data, @data, NULL, NULL, @data,      'CE',   NULL,    0,      10,       NULL,     NULL,      NULL,     0,    NULL,       NULL,       0,           0,         0,          0,           0,       NULL,     0,      0,       0,       0,  @vltotal,    0,          0,      1,     0,       0,       0,     0,     NULL,   NULL,    NULL,       NULL,       0,       @vltotal, NULL,       NULL,      NULL,    NULL,   NULL,    0,         NULL,     NULL,     NULL,          0,       @vltotal,   0,        0,      GETDATE() ,        'S',    NULL,  NULL,     NULL,        NULL,             NULL,         NULL,            NULL,           NULL,     537,      NULL,         NULL,       NULL,       NULL,      NULL,          0,        0,          NULL,      0,          0,        NULL,     NULL,         NULL,        NULL,    NULL,        NULL,    NULL,       0,      NULL,    NULL,         NULL,         0,             0,              0,           NULL,         NULL,  NULL,      NULL,       NULL,      NULL,      NULL,     NULL,       NULL,       NULL,       NULL,    NULL,     NULL,      NULL,     NULL,      NULL,      NULL,          NULL,         NULL,       1,     0,        NULL,          NULL,     NULL,        NULL,         NULL,         NULL,      NULL,     NULL,      NULL,     0,  'CANCELAMENTO REALIZADO VIA INTEGRADOR FIKON', NULL,           NULL,     NULL,         0,       NULL,    NULL,    NULL,       NULL,    NULL,       NULL,             NULL,       NULL,      NULL,       NULL,          NULL,         NULL,      NULL,       NULL,        NULL,            NULL,               NULL,              NULL,               NULL,     NULL,         NULL,           0,       0,      NULL,       NULL,     NULL,   NULL,       NULL,        NULL,    NULL,     NULL,        NULL,         NULL,           NULL,         NULL,         NULL,      NULL,     'N',      NULL,     NULL,    'N',         NULL,            NULL,           NULL,        NULL,              NULL,      NULL,   NULL,        NULL,    NULL,      NULL,          NULL,        NULL,        NULL,          NULL,               NULL,              NULL,              NULL,             NULL,              NULL,              NULL,           NULL,     NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,        @DATAHORAUTC,  0, NULL, 0, 0, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 0, 0)


										-- Update mov_saida
										   UPDATE MOV_SAIDA  WITH (READCOMMITTED) SET   DTCANCEL =  @data , STATUS =  9, statusnfe=9,  NUMORC =  NULL  WHERE 1=1 AND CODFIL =  @codfil AND TPNOTA =  @tpnota AND NUMNOTA =  @numnota AND SERIE =  @serie AND DTNOTA =  @dtnota
				   
										-- insert no jornal
										 exec SP_SEQJORNAL
										 set @seqjornal = ( select LAST_NUMBER from SEQJORNAL  )

										INSERT  INTO MOV_JORNAL( CODFIL, CODMODULO, CODFUNCAO, PRIORIDADE, DATA, HORA, DESCRICAO, OBSERVACAO, ESTACAO, CODUSER, STATUS, REG_ID ) 
										VALUES ( @codfil, 6, 1, 0, CONVERT(VARCHAR,GETDATE(),111), CONVERT(VARCHAR,GETDATE(),108), 'EXCLUSAO DA NOTA FISCAL N.'+ convert(varchar,@numnota), NULL, 'FIKON', 537, 0, @seqjornal) 

									
										
                             end


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

						-- inserindo itens da entrada
						INSERT  INTO ENT_ITENT(CODFIL, TPNOTA, CODREMET, SERIE, NUMNOTA, CODITPROD, NUMPEDCOMP, ITEM, DTNOTA, FILDEST, PRECOUNIT, ALIQICM, VLIPI, PORCIPI, SITUACAO, QTCOMP, QTRECEB,    QTEMBAL, QTESTOQUE, CUSTANT, CODEMBAL, CODPRODDF, STATUS, CUSTANTI, VLDESCONTO, LOCAL,    VLDESPFIN, VLICM, VLDESPESAS, VLCONHEC, VLICMRET, QTDEVOL, VLISENTO, VLOUTRAS,    QTCONSIG, VLBASEICMS,  VLNTRIBUT, TOTESTOQUE,    CODVENDR, ALIQICMRED, ALIQICMSUB, ALIQICMSUBUF, VLBASEICMSSUB, CONVERSAO, VLICMF, VLICMRETF, VLISENTOF,       VLOUTRASF, VLBASEICMSF, VLNTRIBUTF, VLBASEICMSSUBF, QTSALDO, CODCONJU, DESCCOMPLE, VLICMFRT, VLICMSUBREC, COMPLEMENTO, VLOUTRASIPI, VLBASEIPI, VLISENTOIPI, FLATUALIZAPRECO, CODREMETNF, SERIENF,   CMUP,     ALIQIRF, VLDIVIPI, FLREPLICA, CODITCONJU, QTORIG,  HRHORA,      VLPISSUB, VLCOFSUB, CODBARRA, VLDESPACES,  VLFRETE,  VLDESCITEMRAT, VLISS, VLOUTDESP, VLSEGURO, VLSUPINF, VLTOTITEM,   CTF, VLDESCITEM,    VLTOTAL,    QTRETARMAZEM, VLTOTIPI, VLDESPRAT, DPI, CODNATOP, CODNATOPDIF, CODNATOPCOMPL, CODNATOPDIFCOMPL, QTAVARIA, CONDPGTO, VLFUNRURAL, FLAPURACOMISS, FLDEVOLAUTOM, CUE, OBSFISCAL, VLTOTBASEIPI, ALIQINSS, VLBASEINSS, VLINSS, VLIRRF, CODFILANEXO, CODPALLET, FLCROSSDOCKING, CODPRESTSERV, DESCPRESTSERV, VLBASEICMSSUBC, VLICMRETC, VLJUROSVENDA, VLICMSANTEC, MEDGER, VLDESCPRESUMIDOF, VLDESCPRESUMIDOV, VLPIS, VLCOFINS, VLBASEICMD, VLICMD, VLIPIC, VLTOTIPIC, VLICMSGARANTIDO, ALIQCSLL, VLBASECSLL, VLCSLL, VLPIN, PORCIPIENT, VLSUFRAMA, CMUPANT, PPIS, PCONTSOC, PADM, VLICMEG, VLBASEICMEG, VLJUROSFIN, VLJUROS, TABELA, VLICMORIGREPI, VLBASEICMORIGREPI, VLICMREPI, VLFRETETERC, VLICMSFRETETERC, DTVALIDADE, ALIQICMDIF, VLBASEICMDIF, VLICMDIF, VLICMDESCONTOF, VLDESCNOTA, VLPISDESCONTOF, VLCOFDESCONTOF, VLICMCREDITO, ALIQICMCREDITO, CUEPIN, PPIN, TXFUNRURAL, VLBASEPIS, VLBASECOFINS, CODDEVOL, PERCICMREDPISCOFINS, VLBASEICMSGARANTIDO, CUSTOGER,   DTATUEST, ALIQICMDIFANTEC, VLBASEICMDIFANTEC, VLICMDIFANTEC, VLBASEICMSATIVO, ALIQICMSATIVO, VLICMSATIVO, ICMPRESUMIDO, ALIQICMPRES, ICMPRESUMIDOF, CUEI , FLNFCOMPL , ALIQICMREDUF , FLESTOQUE , ALIQICMSGARANTIDO, CSTCOFINS, CSTPIS , ALIQPCTM, VLBASEICMSANTEC, ALIQICMSANTEC, FLREATACBA, VLNTRIBUTD , DESCUNIDTRIBUTAVELNF, FATORCONVTRIBUTAVELNF, VLICMRETV, ORIGEMPROD, ALIQICMCARGALIQST, ALIQFECEP, VLFECEP , VLICMRETSIMPFAT, CUETRANSF, CMUPTRANSF, ALIQICMPART, VLFECEPF, VLFECEPSTF, VLFECEPST, VLICMPARTUFF, VLICMPARTUF, VLICMPARTF, VLICMPART, FLFECEPADIC, CEST , CUETRANSFSAI, CMUPTRANSFSAI, ALIQICMUF, CSTIPI, CODIGO53, CODIGO511, VLAJUSTEITEM, ALIQFECEPST, VLBASEFECEPSTF, VLBASEFECEPF, VLBASEICMPARTUFF , CODIGO52, CODIGO56, VLBASESTRETANT, VLICMSTRETANT, ALIQICMSTRETANT, VLBASEFCPSTRETANT, ALIQFCPSTRETANT, VLFCPSTRETANT, FLPAUTAPRECO, VLBASEICMSEFETIVO, VLICMSEFETIVO , ALIQFEEFMT, VLBASEFEEFMT, VLFEEFMT, VLFEEFMTF, VLSUBSTITUTOSTRETANT , VLICMSDESON, CODMOTDESICMS, VLICMOPERACAO, ALIQICMDIFERIMENTO, VLICMDIFERIDO, VLFECEPSTGARANTIDO, VLICMOPERSTF, VLFECEPOPERSTF, VLNTRIBUTUF , VLDESCBASEPIS, VLDESCBASECOFINS, DESCRPRODNFE, CUSTORE, CUE_RE6763, CMUP_RE6763, CODITPRODABENEF , CLASTRIBCBS , CLASTRIBIBS, CLASTRIBIS, CSTCBS, CSTIBS, CSTIS , VLBASECBS, ALIQCBS, VLCBS, VLBASEIBS, ALIQIBS, VLIBS, VLBASEIBSMUN, ALIQIBSMUN, VLIBSMUN, VLBASEIS, ALIQIS, VLIS) 
						VALUES ( @codfil, 12, @codfil, 'CAN', @numnota, @coditprod, NULL, @item, @data, NULL, @precounit, 0, 0, 0, NULL,                                             @qtcomp,    @qtcomp, NULL,    @fisico,   NULL,      @codembal,       NULL,      1,       NULL,       0,    @local,        NULL,    0,      NULL,        0,        0,        0,        0,   @vltotItem,    NULL,        0,          0,        @totestoque,  NULL,        0,          0,           0,            0,       @conversao,        0,       0,           0,   CASE WHEN @qtcomp <> 0 THEN ROUND(@vltotItem / @qtcomp, 4) ELSE 0 END,       0,          0,             0,         0,        NULL,     NULL,       0,         0,          NULL,        0,            0,          0,           NULL,          0,       NULL,    @cmup,        0,       NULL,     NULL,      NULL,       0, {FN CURTIME()},    0,        0,       NULL,       0,        NULL,         0,          0,      0,          0,       0,       @vltotItem, 0,       0,       @vltotItem,        0,          0,        0,      0,      10,       NULL,          0,              NULL,        NULL,      NULL,      0,           NULL,        NULL,      @cue,  NULL,          0,         NULL,      NULL,    NULL,   NULL,     NULL,        NULL,        NULL,             0,           NULL,            0,         0,             NULL,       NULL,    NULL,        NULL,             NULL,        NULL,    NULL,       0,         0,   NULL,     NULL,          NULL,        NULL,      NULL,     NULL,  NULL,     NULL,      NULL,     NULL,    0,       0,    NULL, NULL,        NULL,       NULL,    NULL,      0,         NULL,           NULL,           NULL,      NULL,            NULL,       NULL,        NULL,        NULL,      NULL,         NULL,         NULL,        NULL,           NULL,             NULL,       NULL,       NULL,   NULL,    NULL,      NULL,       NULL,         NULL,             NULL,               NULL,       NULL,     GETDATE(),        NULL,          NULL,                NULL,         NULL,           NULL,        NULL,         NULL,         NULL,          NULL,   NULL,'N',          NULL,         NULL,            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 'N', NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 0, 0, 0, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)



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

/* ===================== 3. SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA (completa) ===================== */
ALTER PROC [dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]
 @chavenfe varchar(44),
 @coditprod numeric(12),
 @qtcomp numeric(15,2),
 @precounit numeric(15,2),
 @vldescitem numeric(15,5)

as

-- Reescrita em 10/11/2026 (script 09_impostos_SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA.sql): impostos calculados
-- pelas mesmas regras do PDV do Gemco. Ver o cabeçalho do script.

BEGIN TRY

declare @numnota numeric(12,0)
declare @serie varchar(3)
declare @codfil int
declare @codcli numeric(12,0)
declare @hrhora datetime
declare @numpedven numeric(12,0) = 999999
declare @dtnota date = getdate()
declare @codvendr int
declare @peso numeric(12,3)
declare @vlfrete numeric(15,2)
declare @vltotal numeric(15,2)
declare @tpnota varchar(4)
declare @item int
declare @modelonf varchar(4)
declare @UNEMBAL varchar(2)
declare @cmup numeric(15,4)
declare @codsitprod varchar(2)
declare @QTESTOQUE numeric(9,3)
declare @vldescitemrat numeric(15,5)
declare @qtemb numeric(4,0)
declare @cmupi numeric(15,4)
declare @cue numeric(15,4)
declare @CODBARRA numeric(14,0)
declare @fisico numeric(9,3)
declare @resfis numeric(9,3)
declare @cubagem numeric(8,4)
declare @filorig int
declare @qtcompbaixa numeric(9,3)
declare @itensGravados int = 0

-- Cadastro fiscal do produto e da filial
declare @codprod numeric(10,0)
declare @codicms numeric(4,0)
declare @codicmred numeric(4,0)
declare @codicmsub numeric(4,0)
declare @ncm varchar(8)
declare @exipi varchar(3)
declare @origem numeric(2,0)
declare @codcbs numeric(4,0)
declare @codibs numeric(4,0)
declare @uf char(2)
declare @codgrptpnota numeric(2,0)
declare @achou int
declare @prod_txt varchar(20)        -- RAISERROR nao aceita numeric como parametro
declare @ctf_txt varchar(10)

-- ICMS (linhas I, R e S da CAD_IMPTRIBUT)
declare @ctf numeric(2,0)
declare @ctf_i numeric(2,0)
declare @ctf_r numeric(2,0)
declare @ctf_s numeric(2,0)
declare @aliqicm numeric(7,4) = 0
declare @aliqicmred numeric(7,4) = 0
declare @aliqicmsub numeric(7,4) = 0
declare @obs_i varchar(180)
declare @obs_r varchar(180)
declare @obs_s varchar(180)
declare @flnatopsub char(1)
declare @codnatop numeric(3,0)
declare @codnatopcompl numeric(2,0)
declare @obsfiscal varchar(180)
declare @cest varchar(7)
declare @dpi numeric(11,9) = 0

-- Valores do item
declare @U numeric(28,15)                 -- valor unitário líquido (VLTOTAL / QTCOMP)
declare @vlbaseicm numeric(15,2) = 0
declare @vlicm numeric(15,2) = 0
declare @vlisento numeric(15,2) = 0
declare @vlntribut numeric(15,2) = 0
declare @vloutras numeric(15,2) = 0
declare @vlbaseicmsf numeric(22,9) = 0
declare @vlicmf numeric(22,9) = 0
declare @vlisentof numeric(22,9) = 0
declare @vlntributf numeric(22,9) = 0
declare @vloutrasf numeric(22,9) = 0
declare @vlbaseicmd numeric(20,9) = NULL
declare @vlicmd numeric(20,9) = NULL
declare @vlbaseicmsefetivo numeric(15,2) = 0
declare @vlicmsefetivo numeric(15,2) = 0
declare @vlicmoperstf numeric(20,9) = NULL

-- IBPT
declare @aliqibpt numeric(4,2) = NULL
declare @vlibpt numeric(15,2) = NULL
declare @aliqibptest numeric(4,2) = NULL
declare @vlibptest numeric(15,2) = NULL
declare @aliqibptmun numeric(4,2) = NULL
declare @vlibptmun numeric(15,2) = NULL
declare @chaveibpt varchar(20) = NULL
declare @fonteibpt varchar(30) = NULL
declare @versaoibpt varchar(30) = NULL
declare @ibpt_nac numeric(4,2)
declare @ibpt_imp numeric(4,2)
declare @ibpt_est numeric(4,2)
declare @ibpt_mun numeric(4,2)

-- CBS / IBS
declare @aliqcbs numeric(7,4) = 0
declare @aliqibs numeric(7,4) = 0
declare @aliqibsmun numeric(7,4) = 0
declare @cstcbs varchar(4) = NULL
declare @cstibs varchar(4) = NULL
declare @clastribcbs varchar(10) = NULL
declare @clastribibs varchar(10) = NULL
declare @vlbasecbs numeric(20,9) = 0
declare @vlcbs numeric(20,9) = 0
declare @vlbaseibs numeric(20,9) = 0
declare @vlibs numeric(20,9) = 0
declare @vlbaseibsmun numeric(20,9) = 0
declare @vlibsmun numeric(20,9) = 0

set @coditprod = LEFT(@coditprod, LEN(@coditprod) - 1)
set @prod_txt = CONVERT(varchar(20), @coditprod)

--Pegando variaveis que estao na mov_saida
select @filorig = codfil, @codfil = codfil, @codvendr = codvendr, @numnota = NUMNOTA, @serie = SERIE, @tpnota = tpnota, @dtnota = dtnota,
       @codcli = CODCLI, @hrhora = HRHORA, @modelonf = MODELONF
  from dbgemco..mov_saida where CHAVENFE = @chavenfe

IF @codfil IS NULL
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: nota com a chave %s nao encontrada na MOV_SAIDA.', 16, 1, @chavenfe);

IF ISNULL(@qtcomp, 0) <= 0
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: quantidade invalida para o produto (nota %s).', 16, 1, @chavenfe);

set @item = (select count(*)+1 from dbgemco..mov_itsaida where codfil = @codfil and numnota=@numnota and tpnota = @tpnota and serie=@serie and dtnota=@dtnota)

-- Total do item = (quantidade * preço) - desconto (igual ao "total" do produto no payload da FIKON)
set @vltotal = ROUND((@qtcomp * @precounit) - ISNULL(@vldescitem, 0), 2)
set @U = CAST(@vltotal AS numeric(28,15)) / @qtcomp

-- DPI = % de desconto do item (numeric(11,9): não comporta 100; desconto de 100% fica 0)
IF (@qtcomp * @precounit) > 0 AND ISNULL(@vldescitem, 0) < (@qtcomp * @precounit)
    set @dpi = ROUND(ISNULL(@vldescitem, 0) / (@qtcomp * @precounit) * 100, 9, 1)

/* ---------- Cadastro fiscal ---------- */
select @codprod = pro.CODPROD, @codicms = pro.CODICMS, @codicmred = ISNULL(pro.CODICMRED, 0), @codicmsub = ISNULL(pro.CODICMSUB, 0),
       @ncm = pro.NCM, @exipi = pro.EXIPI, @origem = pro.ORIGEM, @codcbs = pro.CODCBS, @codibs = pro.CODIBS
  from dbgemco..CAD_ITPROD itp
  join dbgemco..CAD_PROD pro on pro.CODPROD = itp.CODPROD
 where itp.CODITPROD = @coditprod

IF @codprod IS NULL
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: produto %s nao encontrado na CAD_ITPROD.', 16, 1, @prod_txt);

-- script 16: embalagem do item (antes @qtemb ficava NULL e o extrato de produtos mostrava quantidade 0)
set @qtemb = ISNULL((select top 1 NULLIF(QTEMB, 0) from dbgemco..CAD_EMBAL where CODPROD = @codprod and CODEMBAL = 0), 1)

select @uf = ESTADO from dbgemco..CAD_FILIAL where CODFIL = @codfil
select @codgrptpnota = CODGRPTPNOTA from dbgemco..CAD_TPNOTA where TPNOTA = @tpnota

IF @uf IS NULL OR @codgrptpnota IS NULL
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: filial %d ou tipo de nota %s sem UF / grupo de tipo de nota.', 16, 1, @codfil, @tpnota);

-- Linha 'I' (ICMS): sempre obrigatória, é dela que vem a ALIQICM
select @ctf_i = CTF, @aliqicm = ISNULL(ALIQUOTA, 0), @obs_i = OBSERVACAO
  from dbgemco..CAD_IMPTRIBUT
 where TPIMP = 'I' and CODIMP = @codicms and ESTORIG = @uf and ESTDEST = @uf and CODGRPTPNOTA = @codgrptpnota
set @achou = @@ROWCOUNT

IF @achou = 0
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: produto %s sem tributacao de ICMS (CAD_IMPTRIBUT tipo I) para %s.', 16, 1, @prod_txt, @uf);

IF @codicmred > 0
BEGIN
    select @ctf_r = CTF, @aliqicmred = ISNULL(ALIQUOTA, 0), @obs_r = OBSERVACAO
      from dbgemco..CAD_IMPTRIBUT
     where TPIMP = 'R' and CODIMP = @codicmred and ESTORIG = @uf and ESTDEST = @uf and CODGRPTPNOTA = @codgrptpnota
    set @achou = @@ROWCOUNT

    IF @achou = 0
        RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: produto %s sem a reducao de ICMS (CAD_IMPTRIBUT tipo R) para %s.', 16, 1, @prod_txt, @uf);
END

IF @codicmsub > 0
BEGIN
    select @ctf_s = CTF, @aliqicmsub = ISNULL(ALIQUOTA, 0), @obs_s = OBSERVACAO
      from dbgemco..CAD_IMPTRIBUT
     where TPIMP = 'S' and CODIMP = @codicmsub and ESTORIG = @uf and ESTDEST = @uf and CODGRPTPNOTA = @codgrptpnota
    set @achou = @@ROWCOUNT

    IF @achou = 0
        RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: produto %s sem a substituicao tributaria (CAD_IMPTRIBUT tipo S) para %s.', 16, 1, @prod_txt, @uf);
END

-- CTF: mesma ordem da view PDV_PRODTRIBUT (ST, depois redução, depois ICMS)
set @ctf = CASE WHEN @codicmsub > 0 THEN @ctf_s WHEN @codicmred > 0 THEN @ctf_r ELSE @ctf_i END

set @ctf_txt = ISNULL(CONVERT(varchar(10), @ctf), 'nulo')

IF @ctf IS NULL OR @ctf NOT IN (0, 20, 40, 60, 90)
    RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: produto %s com CTF nao tratado pela integracao (%s). Nada foi gravado.', 16, 1, @prod_txt, @ctf_txt);

/* ---------- ICMS por CTF ---------- */
IF @ctf = 0
BEGIN
    set @vlbaseicm   = @vltotal
    set @vlicm       = ROUND(@vltotal * @aliqicm / 100, 2, 1)
    set @vlbaseicmsf = ROUND(@U, 9)
    set @vlicmf      = ROUND(@U * @aliqicm / 100, 9)
END
ELSE IF @ctf = 20
BEGIN
    set @vlbaseicm   = ROUND(@vltotal * (100 - @aliqicmred) / 100, 2, 1)
    set @vlicm       = ROUND(@vltotal * (100 - @aliqicmred) / 100 * @aliqicm / 100, 2, 1)
    set @vlntribut   = ROUND(@vltotal * @aliqicmred / 100, 2, 1)
    set @vlbaseicmsf = ROUND(@U * (100 - @aliqicmred) / 100, 9)
    set @vlicmf      = ROUND(@U * (100 - @aliqicmred) / 100 * @aliqicm / 100, 9)
    set @vlntributf  = ROUND(@U * @aliqicmred / 100, 9)
END
ELSE IF @ctf = 40
BEGIN
    set @vlisento    = @vltotal
    set @vlisentof   = ROUND(@U, 9)
END
ELSE IF @ctf = 60
BEGIN
    set @vloutras          = @vltotal
    set @vloutrasf         = ROUND(@U, 9)
    set @vlbaseicmsefetivo = @vltotal
    set @vlicmsefetivo     = ROUND(@vltotal * @aliqicm / 100, 2, 1)
    set @vlicmoperstf      = ROUND(@U * @aliqicm / 100, 6)
END
ELSE IF @ctf = 90
BEGIN
    set @vlbaseicmd  = ROUND(@U, 9)
    set @vlicmd      = ROUND(@U * @aliqicm / 100, 9)
END

/* ---------- Natureza de operação, CEST e observação fiscal ---------- */
select @flnatopsub = FLNATOPSUB from dbgemco..CAD_TRIBUT where CTF = @ctf

IF @flnatopsub = 'S'
BEGIN
    set @codnatop = 540        -- CFOP 5.405
    set @codnatopcompl = 5
END
ELSE
BEGIN
    set @codnatop = 510        -- CFOP 5.102
    set @codnatopcompl = 2
END

select @cest = CEST from dbgemco..CAD_NCM where NCM = @ncm

IF @modelonf = '65'
    set @obsfiscal = NULL
ELSE
    set @obsfiscal = CASE WHEN @codicmsub > 0 THEN @obs_s WHEN @codicmred > 0 THEN @obs_r ELSE @obs_i END

/* ---------- IBPT (Lei 12.741), só NFC-e ---------- */
IF @modelonf = '65'
BEGIN
    select top 1 @ibpt_nac = ALIQNAC, @ibpt_imp = ALIQIMP, @ibpt_est = ALIQEST, @ibpt_mun = ALIQMUN,
                 @chaveibpt = CHAVE, @fonteibpt = FONTE, @versaoibpt = VERSAO
      from dbgemco..FIS_TABIBPT
     where CODIGO = @ncm and UF = @uf and TABELA = 0 and ISNULL(EXIPI, '') = ISNULL(@exipi, '')
     order by CASE WHEN @dtnota BETWEEN DTINICIO AND DTFIM THEN 0 ELSE 1 END, DTFIM DESC
    set @achou = @@ROWCOUNT

    IF @achou = 0
    BEGIN
        -- Sem linha para o NCM + EX: o PDV grava tudo zerado e chave/fonte/versão vazias
        set @aliqibpt = 0      set @vlibpt = 0
        set @aliqibptest = 0   set @vlibptest = 0
        set @aliqibptmun = 0   set @vlibptmun = 0
        set @chaveibpt = ''    set @fonteibpt = ''   set @versaoibpt = ''
    END
    ELSE
    BEGIN
        set @aliqibpt    = ISNULL(CASE WHEN @origem IN (1, 2, 3, 8) THEN @ibpt_imp ELSE @ibpt_nac END, 0)
        set @aliqibptest = ISNULL(@ibpt_est, 0)
        set @aliqibptmun = ISNULL(@ibpt_mun, 0)
        set @vlibpt      = ROUND(@vltotal * @aliqibpt / 100, 2, 1)
        set @vlibptest   = ROUND(@vltotal * @aliqibptest / 100, 2, 1)
        set @vlibptmun   = ROUND(@vltotal * @aliqibptmun / 100, 2, 1)
    END
END

/* ---------- CBS / IBS (reforma tributária) ---------- */
select top 1 @aliqcbs = ISNULL(ALIQUOTA, 0), @cstcbs = CST, @clastribcbs = CLASTRIB
  from dbgemco..CAD_IMPTRIBUT_REFORMA
 where TPIMP = 'CBS' and CODIMP = @codcbs and CODGRPTPNOTA = @codgrptpnota and ESTORIG = 'BR' and ESTDEST = 'BR'
   and @dtnota BETWEEN DTVIGENCIAINI AND DTVIGENCIAFIM
 order by DTVIGENCIAINI DESC

select top 1 @aliqibs = ISNULL(ALIQUOTA, 0), @aliqibsmun = ISNULL(ALIQMUNICIPIO, 0), @cstibs = CST, @clastribibs = CLASTRIB
  from dbgemco..CAD_IMPTRIBUT_REFORMA
 where TPIMP = 'IBS' and CODIMP = @codibs and CODGRPTPNOTA = @codgrptpnota and ESTORIG = @uf and ESTDEST = @uf
   and @dtnota BETWEEN DTVIGENCIAINI AND DTVIGENCIAFIM
 order by DTVIGENCIAINI DESC

IF @aliqcbs > 0 OR @aliqibs > 0
BEGIN
    set @vlbasecbs = ROUND(@U, 9, 1)
    set @vlbaseibs = ROUND(@U, 9, 1)
    set @vlcbs     = ROUND(@U * @aliqcbs / 100, 9, 1)
    set @vlibs     = ROUND(@U * @aliqibs / 100, 9, 1)
    IF @aliqibsmun > 0
    BEGIN
        set @vlbaseibsmun = ROUND(@U, 9, 1)
        set @vlibsmun     = ROUND(@U * @aliqibsmun / 100, 9, 1)
    END
END

 DECLARE CR_INSERE_ITENS CURSOR LOCAL FAST_FORWARD FOR

select 0 as cubagem,
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
where itp.CODITPROD=@coditprod


  OPEN CR_INSERE_ITENS
	  FETCH NEXT FROM CR_INSERE_ITENS INTO @cubagem,@UNEMBAL,@codsitprod,@cmup,
	  @cmupi,@cue,@codbarra,@peso

	     WHILE @@FETCH_STATUS = 0

		 BEGIN

		 set  @fisico  = (select fisico from cad_prodloc where codfil=@filorig and coditprod=@coditprod)
		 set  @resfis  = (select resfis from cad_prodloc where codfil=@filorig and coditprod=@coditprod)
		 set  @qtcompbaixa = @qtcomp*-1
		 set @qtestoque = @fisico

INSERT INTO MOV_ITSAIDA (
    CODFIL,
    TPNOTA,
    NUMNOTA,
    DTNOTA,
    SERIE,
    CODITPROD,
    ITEM,
    QTCOMP,
    PRECORDZ,
    PRECOUNIT,
    ALIQICM,
    ALIQICMSUB,
    ALIQICMRED,
    VLIPI,
    LOCAL,
    TPDEPOS,
    PORCIPI,
    MINUTA,
    CUBAGEM,
    CODASSTEC,
    DTASSTEC,
    CODEMBAL,
    DPI,
    DESCCOMPLE,
    STATUS,
    NUMPEDVEN,
    UNEMBAL,
    CODCLI,
    QTRETORN,
    PRECJUR,
    VLFRETE,
    QTDEVOL,
    PRECOUNITLIQ,
    VLSUPINF,
    FLINTEGRACAO,
    CMUP,
    MEDGER,
    HRHORA,
    CODSITPROD,
    RUA,
    BLOCO,
    APTO,
    FILPED,
    DTPROD,
    ALIQICMSUBUF,
    FILORIG,
    IDADEPROD,
    VLBASEICMS,
    VLISENTO,
    VLNTRIBUT,
    VLOUTRAS,
    VLICM,
    QTESTOQUE,
    VLBASEICMSSUB,
    VLICMRET,
    VLDESCITEM,
    VLDESCITEMRAT,
    QTSALDO,
    CODPROM,
    QTEMB,
    VLBASEICMSF,
    VLISENTOF,
    VLNTRIBUTF,
    VLOUTRASF,
    VLICMF,
    VLBASEICMSSUBF,
    VLICMRETF,
    ALIQIRF,
    VLDESPACES,
    VLOUTDESP,
    VLOFERTA,
    COMPLEMENTO,
    CRM,
    VLOUTRASIPI,
    VLBASEIPI,
    VLISENTOIPI,
    FLBXCOMP,
    QTCONSIG,
    QTVOLUME,
    CODITPRODKIT,
    COMISSPER,
    COMISSVAL,
    FLPRODGEN,
    CODVENDR,
    DTVALIDFIM,
    DTVALIDINI,
    VLISS,
    CODNATOP,
    CODNATOPDIF,
    CODNATOPCOMPL,
    CODNATOPDIFCOMPL,
    OBSFISCAL,
    CUEORIG,
    FLDETALHE,
    VLTOTITEM,
    CTF,
    CODPLANOSERV,
    ALIQICMSFRETE,
    VLFRETERAT,
    VLICMSFRETE,
    VLDESPFIN,
    VLICMRETFRT,
    VLSEGURO,
    VLDESPRAT,
    VLTOTAL,
    CMUPI,
    VLTOTIPI,
    FILPEDARMAZEM,
    NUMPEDARMAZEM,
    TIPOPEDARMAZEM,
    VLBASEICMSUBENT,
    VLICMRETENT,
    VLIRRF,
    DTALTERACAO,
    USERIDALT,
    CUE,
    VLTOTBASEIPI,
    FLLOTEVENCTO,
    CODPRESTSERV,
    DESCPRESTSERV,
    FLPRODPROCESS,
    VLJUROSVENDA,
    VLJUROSFIN,
    VLDESCPRESUMIDOF,
    VLDESCPRESUMIDOV,
    VLBASEICMD,
    VLICMD,
    PRECOLISTA,
    ALIQPISCOFINSCSLL,
    VLPISCOFINSCSLL,
    PENCARGO,
    VLJUROS,
    VLBASEISS,
    ALIQISS,
    PRECOORIG,
    VLDESCNOTA,
    ALIQICMREPI,
    VLBASEICMORIGREPI,
    VLICMORIGREPI,
    VLICMREPI,
    ALIQPISSUB,
    ALIQCOFSUB,
    VLPISSUB,
    VLCOFSUB,
    FLSUBSTINTERNA,
    QTVENDAKIT,
    PCONTSOC,
    VLPPIS,
    VLPCONTSOC,
    PPIS,
    ALIQICMDIF,
    VLBASEICMDIF,
    VLICMDIF,
    VLICMDESCONTOF,
    VLTAC,
    CODTECNICO,
    VLPISDESCONTOF,
    VLCOFDESCONTOF,
    ALIQICMDIFSAI,
    VLBASEICMSDIFSAI,
    VLICMDIFSAI,
    NUMORC,
    CUSTOGER,
    ALIQICMSATIVO,
    VLBASEICMSATIVO,
    VLICMSATIVO,
    FLATUTRAN,
    FLPREINDIG,
    VLPISRET,
    VLCSLLRET,
    VLIRRET,
    VLCOFINSRET,
    ALIQPCTM,
    ALIQICMREDUF,
    VLNTRIBUTD,
    DESCUNIDTRIBUTAVELNF,
    FATORCONVTRIBUTAVELNF,
    VLICMRETV,
    ALIQICMCREDITO,
    VLICMCREDITO,
    ORIGEMPROD,
    DESCLICITACAO,
    ALIQIBPT,
    VLIBPT,
    VERSAOIBPT,
    NUMFCI,
    CONVERSAO,
    VLCUSTOIMP,
    OBSCOMPLPROD,
    FLESCFISCALDIF,
    CFOPNOTA,
    CTFNOTA,
    CODJUST,
    CHAVEIBPT,
    FONTEIBPT,
    ALIQIBPTEST,
    VLIBPTEST,
    ALIQIBPTMUN,
    VLIBPTMUN,
    VLICMSRECUPTRANSF,
    ALIQICMUF,
    VLICMSSTRECUPTRANSF,
    ALIQFECEP,
    ALIQICMPART,
    VLFECEPF,
    VLFECEP,
    VLFECEPSTF,
    VLFECEPST,
    VLICMPARTUFF,
    VLICMPARTUF,
    VLICMPARTF,
    VLICMPART,
    FLFECEPADIC,
    CEST,
    VLBASEPIS,
    VLBASECOFINS,
    CUETRANSF,
    CMUPTRANSF,
    CSTIPI,
    CSTPIS,
    CSTCOFINS,
    CODBARRA,
    VLBASEFECEPF,
    VLBASEFECEPSTF,
    ALIQFECEPST,
    VLBASEICMPARTUFF,
    CODIGO53,
    VLAJUSTEITEM,
    CODIGO52,
    CODIGO56,
    VLBASESTRETANT,
    VLICMSTRETANT,
    VLREMGST,
    VLBASEFCPSTRETANT,
    ALIQFCPSTRETANT,
    VLFCPSTRETANT,
    VLBASEICMSEFETIVO,
    VLICMSEFETIVO,
    VLICMSGARANTIDO,
    VLBASEICMSGARANTIDO,
    VLICMEG,
    VLBASEICMEG,
    VLSUBSTITUTOSTRETANT,
    VLICMOPERACAO,
    ALIQICMDIFERIMENTO,
    VLICMDIFERIDO,
    VLICMSDESON,
    CODMOTDESICMS,
    VLFECEPSTGARANTIDO,
    VLBASEDESONDIFERF,
    VLBASEICMUE,
    VLICMUE,
    VLBASEICMSSTUE,
    VLICMSSTUE,
    VLFECEPSTUE,
    VLBASEICMMUP,
    VLICMMUP,
    VLBASEICMSSTMUP,
    VLICMSSTMUP,
    VLFECEPSTMUP,
    VLICMOPERSTF,
    VLFECEPOPERSTF,
    VLFECEPUE,
    VLFECEPMUP,
    VLNTRIBUTUF,
    VLDESCBASEPIS,
    VLDESCBASECOFINS,
    CUSTORE,
    CUE_RE6763,
    CMUP_RE6763,
    VLCASHBACKPROFISCONSTRU,
    CODITPRODBENEF,
    CLASTRIBCBS,
    CLASTRIBIBS,
    CLASTRIBIS,
    CSTCBS,
    CSTIBS,
    CSTIS,
    VLBASECBS,
    ALIQCBS,
    VLCBS,
    VLBASEIBS,
    ALIQIBS,
    VLIBS,
    VLBASEIBSMUN,
    ALIQIBSMUN,
    VLIBSMUN,
    VLBASEIS,
    ALIQIS,
    VLIS,
    PERCREDUTOR
)
VALUES (
    @codfil,                        -- CODFIL
    @tpnota,                        -- TPNOTA
    @numnota,                       -- NUMNOTA
    @dtnota,                        -- DTNOTA
    @serie,                         -- SERIE
    @coditprod,                     -- CODITPROD
    @item,                          -- ITEM
    @qtcomp,                        -- QTCOMP
    NULL,                           -- PRECORDZ
    @precounit,                     -- PRECOUNIT
    @aliqicm,                       -- ALIQICM  [imposto]
    @aliqicmsub,                    -- ALIQICMSUB  [imposto]
    @aliqicmred,                    -- ALIQICMRED  [imposto]
    0,                              -- VLIPI
    1,                              -- LOCAL
    'L',                            -- TPDEPOS
    0,                              -- PORCIPI
    NULL,                           -- MINUTA
    @cubagem,                       -- CUBAGEM
    NULL,                           -- CODASSTEC
    NULL,                           -- DTASSTEC
    0,                              -- CODEMBAL
    @dpi,                           -- DPI  [imposto]
    NULL,                           -- DESCCOMPLE
    2,                              -- STATUS
    @numpedven,                     -- NUMPEDVEN
    @UNEMBAL,                       -- UNEMBAL
    @codcli,                        -- CODCLI
    NULL,                           -- QTRETORN
    0,                              -- PRECJUR
    @vlfrete,                       -- VLFRETE
    0,                              -- QTDEVOL
    @precounit,                     -- PRECOUNITLIQ
    0,                              -- VLSUPINF
    NULL,                           -- FLINTEGRACAO
    @cmup,                          -- CMUP
    0,                              -- MEDGER
    @hrhora,                        -- HRHORA
    @codsitprod,                    -- CODSITPROD
    NULL,                           -- RUA
    0,                              -- BLOCO
    NULL,                           -- APTO
    @codfil,                        -- FILPED
    NULL,                           -- DTPROD
    0,                              -- ALIQICMSUBUF  [imposto]
    @codfil,                        -- FILORIG
    NULL,                           -- IDADEPROD
    @vlbaseicm,                     -- VLBASEICMS  [imposto]
    @vlisento,                      -- VLISENTO  [imposto]
    @vlntribut,                     -- VLNTRIBUT  [imposto]
    @vloutras,                      -- VLOUTRAS  [imposto]
    @vlicm,                         -- VLICM  [imposto]
    @QTESTOQUE,                     -- QTESTOQUE
    0,                              -- VLBASEICMSSUB  [imposto]
    0,                              -- VLICMRET  [imposto]
    @vldescitem,                    -- VLDESCITEM
    @vldescitemrat,                 -- VLDESCITEMRAT
    0,                              -- QTSALDO
    0,                              -- CODPROM
    @qtemb,                         -- QTEMB
    @vlbaseicmsf,                   -- VLBASEICMSF  [imposto]
    @vlisentof,                     -- VLISENTOF  [imposto]
    @vlntributf,                    -- VLNTRIBUTF  [imposto]
    @vloutrasf,                     -- VLOUTRASF  [imposto]
    @vlicmf,                        -- VLICMF  [imposto]
    0,                              -- VLBASEICMSSUBF
    0,                              -- VLICMRETF
    0,                              -- ALIQIRF
    0,                              -- VLDESPACES
    0,                              -- VLOUTDESP
    0,                              -- VLOFERTA
    NULL,                           -- COMPLEMENTO
    0,                              -- CRM
    0,                              -- VLOUTRASIPI
    0,                              -- VLBASEIPI
    0,                              -- VLISENTOIPI
    NULL,                           -- FLBXCOMP
    0,                              -- QTCONSIG
    0,                              -- QTVOLUME
    NULL,                           -- CODITPRODKIT
    NULL,                           -- COMISSPER
    NULL,                           -- COMISSVAL
    NULL,                           -- FLPRODGEN
    @CODVENDR,                      -- CODVENDR
    NULL,                           -- DTVALIDFIM
    NULL,                           -- DTVALIDINI
    0,                              -- VLISS
    @codnatop,                      -- CODNATOP  [imposto]
    NULL,                           -- CODNATOPDIF
    @codnatopcompl,                 -- CODNATOPCOMPL  [imposto]
    NULL,                           -- CODNATOPDIFCOMPL
    @obsfiscal,                     -- OBSFISCAL  [imposto]
    NULL,                           -- CUEORIG
    NULL,                           -- FLDETALHE
    @vltotal,                       -- VLTOTITEM
    @ctf,                           -- CTF  [imposto]
    NULL,                           -- CODPLANOSERV
    0,                              -- ALIQICMSFRETE
    0,                              -- VLFRETERAT
    0,                              -- VLICMSFRETE
    0,                              -- VLDESPFIN
    NULL,                           -- VLICMRETFRT
    0,                              -- VLSEGURO
    0,                              -- VLDESPRAT
    @vltotal,                       -- VLTOTAL
    @cmupi,                         -- CMUPI
    0,                              -- VLTOTIPI
    NULL,                           -- FILPEDARMAZEM
    NULL,                           -- NUMPEDARMAZEM
    NULL,                           -- TIPOPEDARMAZEM
    NULL,                           -- VLBASEICMSUBENT
    NULL,                           -- VLICMRETENT
    0,                              -- VLIRRF
    NULL,                           -- DTALTERACAO
    NULL,                           -- USERIDALT
    @cue,                           -- CUE
    0,                              -- VLTOTBASEIPI
    'N',                            -- FLLOTEVENCTO
    0,                              -- CODPRESTSERV
    NULL,                           -- DESCPRESTSERV
    'N',                            -- FLPRODPROCESS
    NULL,                           -- VLJUROSVENDA
    0,                              -- VLJUROSFIN
    0,                              -- VLDESCPRESUMIDOF
    0,                              -- VLDESCPRESUMIDOV
    @vlbaseicmd,                    -- VLBASEICMD  [imposto]
    @vlicmd,                        -- VLICMD  [imposto]
    0,                              -- PRECOLISTA
    0,                              -- ALIQPISCOFINSCSLL
    0,                              -- VLPISCOFINSCSLL
    0,                              -- PENCARGO
    0,                              -- VLJUROS
    0,                              -- VLBASEISS
    0,                              -- ALIQISS
    @precounit,                     -- PRECOORIG
    0,                              -- VLDESCNOTA
    0,                              -- ALIQICMREPI
    0,                              -- VLBASEICMORIGREPI
    0,                              -- VLICMORIGREPI
    0,                              -- VLICMREPI
    0,                              -- ALIQPISSUB
    0,                              -- ALIQCOFSUB
    0,                              -- VLPISSUB
    0,                              -- VLCOFSUB
    NULL,                           -- FLSUBSTINTERNA
    0,                              -- QTVENDAKIT
    0,                              -- PCONTSOC
    0,                              -- VLPPIS
    0,                              -- VLPCONTSOC
    0,                              -- PPIS
    0,                              -- ALIQICMDIF
    0,                              -- VLBASEICMDIF
    0,                              -- VLICMDIF
    0,                              -- VLICMDESCONTOF
    0,                              -- VLTAC
    0,                              -- CODTECNICO
    0,                              -- VLPISDESCONTOF
    0,                              -- VLCOFDESCONTOF
    0,                              -- ALIQICMDIFSAI
    0,                              -- VLBASEICMSDIFSAI
    0,                              -- VLICMDIFSAI
    0,                              -- NUMORC
    NULL,                           -- CUSTOGER
    0,                              -- ALIQICMSATIVO
    0,                              -- VLBASEICMSATIVO
    0,                              -- VLICMSATIVO
    NULL,                           -- FLATUTRAN
    'N',                            -- FLPREINDIG
    0,                              -- VLPISRET
    0,                              -- VLCSLLRET
    0,                              -- VLIRRET
    0,                              -- VLCOFINSRET
    0,                              -- ALIQPCTM
    0,                              -- ALIQICMREDUF
    0,                              -- VLNTRIBUTD
    NULL,                           -- DESCUNIDTRIBUTAVELNF
    NULL,                           -- FATORCONVTRIBUTAVELNF
    0,                              -- VLICMRETV
    0,                              -- ALIQICMCREDITO
    0,                              -- VLICMCREDITO
    NULL,                           -- ORIGEMPROD  [imposto]
    NULL,                           -- DESCLICITACAO
    @aliqibpt,                      -- ALIQIBPT  [imposto]
    @vlibpt,                        -- VLIBPT  [imposto]
    @versaoibpt,                    -- VERSAOIBPT  [imposto]
    NULL,                           -- NUMFCI
    1,                              -- CONVERSAO
    NULL,                           -- VLCUSTOIMP
    NULL,                           -- OBSCOMPLPROD
    NULL,                           -- FLESCFISCALDIF
    0,                              -- CFOPNOTA
    NULL,                           -- CTFNOTA
    NULL,                           -- CODJUST
    @chaveibpt,                     -- CHAVEIBPT  [imposto]
    @fonteibpt,                     -- FONTEIBPT  [imposto]
    @aliqibptest,                   -- ALIQIBPTEST  [imposto]
    @vlibptest,                     -- VLIBPTEST  [imposto]
    @aliqibptmun,                   -- ALIQIBPTMUN  [imposto]
    @vlibptmun,                     -- VLIBPTMUN  [imposto]
    NULL,                           -- VLICMSRECUPTRANSF
    NULL,                           -- ALIQICMUF  [imposto]
    NULL,                           -- VLICMSSTRECUPTRANSF
    0,                              -- ALIQFECEP
    0,                              -- ALIQICMPART
    0,                              -- VLFECEPF
    0,                              -- VLFECEP
    0,                              -- VLFECEPSTF
    0,                              -- VLFECEPST
    0,                              -- VLICMPARTUFF
    0,                              -- VLICMPARTUF
    0,                              -- VLICMPARTF
    0,                              -- VLICMPART
    'N',                            -- FLFECEPADIC
    @cest,                          -- CEST  [imposto]
    0,                              -- VLBASEPIS
    0,                              -- VLBASECOFINS
    NULL,                           -- CUETRANSF
    NULL,                           -- CMUPTRANSF
    NULL,                           -- CSTIPI
    NULL,                           -- CSTPIS
    NULL,                           -- CSTCOFINS
    @CODBARRA,                      -- CODBARRA
    0,                              -- VLBASEFECEPF
    0,                              -- VLBASEFECEPSTF
    0,                              -- ALIQFECEPST
    0,                              -- VLBASEICMPARTUFF
    NULL,                           -- CODIGO53
    NULL,                           -- VLAJUSTEITEM
    NULL,                           -- CODIGO52
    NULL,                           -- CODIGO56
    0,                              -- VLBASESTRETANT
    0,                              -- VLICMSTRETANT
    0,                              -- VLREMGST
    0,                              -- VLBASEFCPSTRETANT
    0,                              -- ALIQFCPSTRETANT
    0,                              -- VLFCPSTRETANT
    @vlbaseicmsefetivo,             -- VLBASEICMSEFETIVO  [imposto]
    @vlicmsefetivo,                 -- VLICMSEFETIVO  [imposto]
    NULL,                           -- VLICMSGARANTIDO
    NULL,                           -- VLBASEICMSGARANTIDO
    NULL,                           -- VLICMEG
    NULL,                           -- VLBASEICMEG
    0,                              -- VLSUBSTITUTOSTRETANT
    NULL,                           -- VLICMOPERACAO
    NULL,                           -- ALIQICMDIFERIMENTO
    NULL,                           -- VLICMDIFERIDO
    NULL,                           -- VLICMSDESON
    NULL,                           -- CODMOTDESICMS
    NULL,                           -- VLFECEPSTGARANTIDO
    NULL,                           -- VLBASEDESONDIFERF
    0,                              -- VLBASEICMUE
    0,                              -- VLICMUE
    0,                              -- VLBASEICMSSTUE
    0,                              -- VLICMSSTUE
    0,                              -- VLFECEPSTUE
    0,                              -- VLBASEICMMUP
    0,                              -- VLICMMUP
    0,                              -- VLBASEICMSSTMUP
    0,                              -- VLICMSSTMUP
    0,                              -- VLFECEPSTMUP
    @vlicmoperstf,                  -- VLICMOPERSTF  [imposto]
    0,                              -- VLFECEPOPERSTF
    0,                              -- VLFECEPUE
    0,                              -- VLFECEPMUP
    0,                              -- VLNTRIBUTUF
    0,                              -- VLDESCBASEPIS
    0,                              -- VLDESCBASECOFINS
    0,                              -- CUSTORE
    0,                              -- CUE_RE6763
    0,                              -- CMUP_RE6763
    0,                              -- VLCASHBACKPROFISCONSTRU
    0,                              -- CODITPRODBENEF
    @clastribcbs,                   -- CLASTRIBCBS  [imposto]
    @clastribibs,                   -- CLASTRIBIBS  [imposto]
    NULL,                           -- CLASTRIBIS
    @cstcbs,                        -- CSTCBS  [imposto]
    @cstibs,                        -- CSTIBS  [imposto]
    NULL,                           -- CSTIS
    @vlbasecbs,                     -- VLBASECBS  [imposto]
    @aliqcbs,                       -- ALIQCBS  [imposto]
    @vlcbs,                         -- VLCBS  [imposto]
    @vlbaseibs,                     -- VLBASEIBS  [imposto]
    @aliqibs,                       -- ALIQIBS  [imposto]
    @vlibs,                         -- VLIBS  [imposto]
    @vlbaseibsmun,                  -- VLBASEIBSMUN  [imposto]
    @aliqibsmun,                    -- ALIQIBSMUN  [imposto]
    @vlibsmun,                      -- VLIBSMUN  [imposto]
    0,                              -- VLBASEIS
    0,                              -- ALIQIS
    0,                              -- VLIS
    NULL                            -- PERCREDUTOR  [imposto]
)

set @itensGravados = @itensGravados + 1

UPDATE MOV_ITPED  WITH (READCOMMITTED) SET   DTNOTA =  @dtnota, QTEMITIDO =  @qtcomp, STATUS =  6, NUMNOTA =  @numnota, TPNOTA =  @tpnota, QTFAT =  QTFAT + @qtcomp, QTLIB =  QTLIB - @qtcomp, QTCORTE =  case when qtcorte> 0 then QTCORTE - @qtcomp else 0 end  WHERE 1=1 AND MOV_ITPED.CODFIL = @codfil AND MOV_ITPED.NUMPEDVEN = @numpedven AND MOV_ITPED.TIPOPED = 0 AND MOV_ITPED.CODITPROD = @coditprod AND MOV_ITPED.ITEM = @item

exec SPU_PROLOCI 1, @codfil, 'L', @coditprod, @qtcompbaixa, @qtcompbaixa, 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0

INSERT INTO MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,    FISICO,  RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO, QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO,    FISICOPOS,         RESFISPOS,       ENCOMENDAPOS, FUTUROPOS, LOGICOPOS, TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG,  DTPROC,           ROTINA,                  COMANDOSQL,                                                                                                                                                                                   IDENTPROC )
VALUES ( @codfil, @numpedven,@numnota, GETDATE(),@tpnota,                   'S',     3,    @coditprod, @fisico,  @resfis,     0,         0,      0,       0,      0,         0,           0,       -@qtcomp,      'FISICO;RESFIS;', 'N',   @fisico-@qtcomp,  @resfis-@qtcomp ,         0,           0,         0,        0,           0,              0,             0,         @codfil, getdate(), 'GRAVAITENSNOTAFISCAL', '{CALL SPU_PROLOCI(1, '+convert(varchar,@codfil)+', L, '+convert(varchar,@coditprod)+', -'+convert(varchar,@qtcomp)+', -'+convert(varchar,@qtcomp)+', 0, 0, 0, 0, 0, 0, 0, NULL , 0, NULL , NULL , NULL , NULL , 0, 0, 0, 0, 0)} ',                                    'INTEGRADOR FIKON' )




     FETCH NEXT FROM CR_INSERE_ITENS INTO @cubagem,@UNEMBAL,@codsitprod,@cmup,
	  @cmupi,@cue,@codbarra,@peso



  END

  CLOSE CR_INSERE_ITENS
  DEALLOCATE CR_INSERE_ITENS

  -- Antes o item era pulado sem aviso quando faltava código de barras, preço, custo ou embalagem
  IF @itensGravados = 0
      RAISERROR('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA: produto %s sem codigo de barras, preco/custo da filial 8 ou embalagem; item nao gravado.', 16, 1, @prod_txt);

 /* ---------- Totais do cabeçalho (todos os itens da nota) ---------- */
 ;WITH it AS (
     select SUM(VLTOTAL) AS vltotal,
            SUM(ISNULL(VLBASEICMS, 0)) AS vlbaseicms,
            SUM(ISNULL(VLICM, 0)) AS vlicm,
            SUM(ISNULL(VLOUTRAS, 0)) AS vloutras,
            SUM(ISNULL(VLISENTO, 0)) AS vlisento,
            ROUND(SUM(ISNULL(VLBASEICMD, 0) * QTCOMP), 2, 1) AS vlbaseicmd,
            ROUND(SUM(ISNULL(VLICMD, 0) * QTCOMP), 2, 1) AS vlicmd,
            SUM(ISNULL(VLIBPT, 0)) AS vlibpt,
            SUM(ISNULL(VLIBPTEST, 0)) AS vlibptest,
            SUM(ISNULL(VLIBPTMUN, 0)) AS vlibptmun,
            MAX(CHAVEIBPT) AS chaveibpt,
            MAX(FONTEIBPT) AS fonteibpt,
            ROUND(SUM(ISNULL(VLBASECBS, 0) * QTCOMP), 2) AS vlbasecbs,
            ROUND(SUM(ISNULL(VLCBS, 0) * QTCOMP), 2, 1) AS vlcbs,
            ROUND(SUM(ISNULL(VLIBS, 0) * QTCOMP), 2, 1) AS vlibs,
            ROUND(SUM(ISNULL(VLIBSMUN, 0) * QTCOMP), 2, 1) AS vlibsmun
       from dbgemco..MOV_ITSAIDA
      where CODFIL = @codfil and TPNOTA = @tpnota and NUMNOTA = @numnota and SERIE = @serie and DTNOTA = @dtnota
 )
 UPDATE s SET
        VLTOTAL     = it.vltotal,
        VLMERCAD    = it.vltotal + ISNULL(s.VLDESCONTO, 0),
        VLBASEICMS  = it.vlbaseicms,
        VLICM       = it.vlicm,
        VLOUTRAS    = it.vloutras,
        VLISENTO    = it.vlisento,
        VLBASEICMD  = it.vlbaseicmd,
        VLICMD      = it.vlicmd,
        VLIBPT      = CASE WHEN s.MODELONF = '65' THEN it.vlibpt ELSE s.VLIBPT END,
        VLIBPTEST   = CASE WHEN s.MODELONF = '65' THEN it.vlibptest ELSE s.VLIBPTEST END,
        VLIBPTMUN   = CASE WHEN s.MODELONF = '65' THEN it.vlibptmun ELSE s.VLIBPTMUN END,
        ALIQIBPT    = CASE WHEN s.MODELONF = '65' THEN CASE WHEN it.vltotal > 0 THEN ROUND(it.vlibpt / it.vltotal * 100, 2) ELSE 0 END ELSE s.ALIQIBPT END,
        ALIQIBPTEST = CASE WHEN s.MODELONF = '65' THEN CASE WHEN it.vltotal > 0 THEN ROUND(it.vlibptest / it.vltotal * 100, 2) ELSE 0 END ELSE s.ALIQIBPTEST END,
        ALIQIBPTMUN = CASE WHEN s.MODELONF = '65' THEN CASE WHEN it.vltotal > 0 THEN ROUND(it.vlibptmun / it.vltotal * 100, 2) ELSE 0 END ELSE s.ALIQIBPTMUN END,
        CHAVEIBPT   = CASE WHEN s.MODELONF = '65' THEN it.chaveibpt ELSE s.CHAVEIBPT END,
        FONTEIBPT   = CASE WHEN s.MODELONF = '65' THEN it.fonteibpt ELSE s.FONTEIBPT END,
        -- CBS/IBS do cabeçalho: no modelo 65 o trigger não totaliza (mantém o que o item trouxe); no 55 ele totaliza
        VLBASECBS    = CASE WHEN s.MODELONF = '65' THEN it.vlbasecbs ELSE s.VLBASECBS END,
        VLCBS        = CASE WHEN s.MODELONF = '65' THEN it.vlcbs ELSE s.VLCBS END,
        VLBASEIBS    = CASE WHEN s.MODELONF = '65' THEN it.vlbasecbs ELSE s.VLBASEIBS END,
        VLIBS        = CASE WHEN s.MODELONF = '65' THEN it.vlibs ELSE s.VLIBS END,
        VLBASEIBSMUN = CASE WHEN s.MODELONF = '65' THEN it.vlbasecbs ELSE s.VLBASEIBSMUN END,
        VLIBSMUN     = CASE WHEN s.MODELONF = '65' THEN it.vlibsmun ELSE s.VLIBSMUN END,
        CODNATOP         = CASE WHEN s.MODELONF = '65' THEN 510 ELSE s.CODNATOP END,
        CODNATOPCOMPL    = CASE WHEN s.MODELONF = '65' THEN 2 ELSE s.CODNATOPCOMPL END,
        CODNATOPDIF      = CASE WHEN s.MODELONF = '65' THEN 540 ELSE s.CODNATOPDIF END,
        CODNATOPDIFCOMPL = CASE WHEN s.MODELONF = '65' THEN 5 ELSE s.CODNATOPDIFCOMPL END
   from dbgemco..MOV_SAIDA s
  cross join it
  where s.CODFIL = @codfil and s.TPNOTA = @tpnota and s.NUMNOTA = @numnota and s.SERIE = @serie and s.DTNOTA = @dtnota
    and it.vltotal IS NOT NULL      -- nunca apaga os totais com NULL



  END TRY

  BEGIN CATCH

    DECLARE @Mensagem NVARCHAR(MAX);

    SET @Mensagem =
        'Erro ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) +
        ' na linha ' + CAST(ERROR_LINE() AS VARCHAR(10)) +
        ': ' + ERROR_MESSAGE();

    -- Fecha o cursor ANTES do THROW (antes ficava depois e nunca era executado)
    IF CURSOR_STATUS('local','CR_INSERE_ITENS') >= -1
    BEGIN
        IF CURSOR_STATUS('local','CR_INSERE_ITENS') >= 0
            CLOSE CR_INSERE_ITENS;
        DEALLOCATE CR_INSERE_ITENS;
    END;

    THROW 50000, @Mensagem, 1;

  END CATCH
GO

SET NOEXEC OFF;
GO

-- Conferência: as 2 procedures devem ter o ajuste e as cópias devem existir.
SELECT o.name, o.modify_date,
       CASE WHEN o.name NOT LIKE '%[_]BKP[_]%'
            THEN CASE WHEN CHARINDEX('script 16', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script16
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_CANCELAR_NOTA', 'SP_FIKON_CANCELAR_NOTA_BKP_SCRIPT16',
                  'SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA', 'SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT16')
 ORDER BY o.name;
GO
