/*
  34 - DEV: atualiza a integração FIKON com as versões da PRODUÇÃO (scripts 20 a 33)  -  24/11/2026
  Base: DEV (DB-TREINO 10.1.5.226), banco dbgemco.  NÃO rodar na produção (o script confere o servidor).

  As procedures abaixo vão com o texto EXATO que está hoje na produção (conferido por SHA-256 em 24/11):
      SP_FIKON_CANCELAR_NOTA                 DEV: script 16  -> produção: scripts 20, 23 e 27
      SP_FIKON_NOTA_GRAVAR_FINANCEIRO        DEV: original   -> produção: script 21 (caixa pela FIKON_CAD_CAIXA)
      SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO  DEV: original   -> produção: script 24 (série da venda)
      SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA       DEV: script 13  -> produção: script 29 (NUMNFE/DIGNFE/NUMCOO)
      SP_FIKON_INTEGRA_MOV_ITSAIDA           DEV: script 13  -> produção: script 32 (TPPED R/P)
      SP_FIKON_ATUALIZA_STATUS_PEDIDO        DEV: versão de julho (fila em dbAplicativos..PEDIDOS_GEMCO_FIKON)
                                             -> produção: script 33 (fila FIKON_INTEGRACAO_PEDIDO, caixa FIKON_CAD_CAIXA)
  Já estavam iguais nas duas bases: SP_FIKON_INTEGRA_DEVOLUCAO, SP_FIKON_INTEGRA_ITEM_DEVOLUCAO,
  SP_FIKON_INTEGRA_MOV_SAIDA, SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA e FN_FIKON_MODELO_NF.

  Também:
    - cria a tabela FIKON_CAD_CAIXA (não existe no DEV) com a mesma estrutura e as mesmas linhas da produção:
      filial 15 série U05 -> caixa 4 / operador 24; filial 15 série U06 -> caixa 3 / operador 24;
    - inclui no FIKON_DEPARA_BANDEIRA as variações com "Débito"/"Crédito" do script 31 (só as que faltarem).

  Como rodar: no SSMS, conectado no DEV, banco dbgemco, executar o script INTEIRO (F5).
    - O bloco 1 confere a versão de cada procedure no DEV e guarda cópias <nome>_BKP_DEV34.
      Se alguma estiver diferente do esperado, o script para (SET NOEXEC ON) e nada é alterado.
  Para voltar atrás: abrir a cópia <nome>_BKP_DEV34, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

IF @@SERVERNAME <> 'DB-TREINO'
BEGIN
    RAISERROR('Este script e so para o DEV (DB-TREINO). Nada foi alterado.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ===================== 1. Conferência das versões e cópias de segurança ===================== */
DECLARE @erro varchar(4000) = '';
DECLARE @def nvarchar(max);

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA'));
IF @def IS NULL SET @erro = @erro + 'SP_FIKON_CANCELAR_NOTA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) NOT IN (0x35217748E0B0BA22DE2727187BC0D3B79E783F30F19CA8E2808F1507FB05230B, 0x86D37BFD01B20377E24D798B051DE01B04356AAD25857C37284B954C25F974E3) AND CHARINDEX(N'script 27', @def) = 0
    SET @erro = @erro + 'SP_FIKON_CANCELAR_NOTA esta numa versao diferente da esperada. ';

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO'));
IF @def IS NULL SET @erro = @erro + 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) NOT IN (0xE8DEF2137DDED11FB1C57F82D187EB02F1E9DDE7DC9C15502391BE3FD11980B2, 0xA116BF4E7F301CFAD3AC510146C6490D74459FD79F5AF5270DF5B6C2E9A03BB7) AND CHARINDEX(N'script 21', @def) = 0
    SET @erro = @erro + 'SP_FIKON_NOTA_GRAVAR_FINANCEIRO esta numa versao diferente da esperada. ';

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO'));
IF @def IS NULL SET @erro = @erro + 'SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) NOT IN (0xA89ACC4D2C9DADB1D5C559B6D38ADCFCE25FEBA9945E1A6F6B694E5053D89A0F, 0x3D50767EB27C8FDAA3A0A028E4256F63572A7CFD3B4CE699371781546A11FB3D) AND CHARINDEX(N'script 24', @def) = 0
    SET @erro = @erro + 'SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO esta numa versao diferente da esperada. ';

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA'));
IF @def IS NULL SET @erro = @erro + 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) NOT IN (0x92CE1E60BAE06121BFA9EFF667FE5BAE9E4C880351BB20C0D9DC2ACB55278EDD, 0x609AF1584D2146614E478893439FCA252665D2667B177007955ECAC3BE0F3E37) AND CHARINDEX(N'script 29', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA esta numa versao diferente da esperada. ';

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA'));
IF @def IS NULL SET @erro = @erro + 'SP_FIKON_INTEGRA_MOV_ITSAIDA nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) NOT IN (0x4EED4F4FF63BDDA6EEE7C78A28238F72E1A9A2FFFEE17F491D737FE0D8E4D347, 0xC574DC32F479CC8203E3F6E34250624374D6C9086DC19CE151B6A3A4C0D64DA3) AND CHARINDEX(N'script 32', @def) = 0
    SET @erro = @erro + 'SP_FIKON_INTEGRA_MOV_ITSAIDA esta numa versao diferente da esperada. ';

SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO'));
IF @def IS NULL SET @erro = @erro + 'SP_FIKON_ATUALIZA_STATUS_PEDIDO nao existe. ';
ELSE IF HASHBYTES('SHA2_256', @def) NOT IN (0x0EBAF60B0BED1EF23A11EA6C5C12557A4B103EE9CE3671F9A117DF8576D2ABCC, 0x0D564435AB1F40D9161B54EECE28EA8580C76D37F555CF86BFF7D5C7155E075A) AND CHARINDEX(N'script 33', @def) = 0
    SET @erro = @erro + 'SP_FIKON_ATUALIZA_STATUS_PEDIDO esta numa versao diferente da esperada. ';


IF @erro = ''
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_DEV34') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA')), N'SP_FIKON_CANCELAR_NOTA', N'SP_FIKON_CANCELAR_NOTA_BKP_DEV34');
        EXEC sys.sp_executesql @def;
        IF OBJECT_ID('dbo.SP_FIKON_CANCELAR_NOTA_BKP_DEV34') IS NULL SET @erro = @erro + 'copia de SP_FIKON_CANCELAR_NOTA nao criada. ';
    END
    IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_DEV34') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO')), N'SP_FIKON_NOTA_GRAVAR_FINANCEIRO', N'SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_DEV34');
        EXEC sys.sp_executesql @def;
        IF OBJECT_ID('dbo.SP_FIKON_NOTA_GRAVAR_FINANCEIRO_BKP_DEV34') IS NULL SET @erro = @erro + 'copia de SP_FIKON_NOTA_GRAVAR_FINANCEIRO nao criada. ';
    END
    IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_DEV34') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO')), N'SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO', N'SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_DEV34');
        EXEC sys.sp_executesql @def;
        IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_DEV34') IS NULL SET @erro = @erro + 'copia de SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO nao criada. ';
    END
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_DEV34') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA')), N'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA', N'SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_DEV34');
        EXEC sys.sp_executesql @def;
        IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA_BKP_DEV34') IS NULL SET @erro = @erro + 'copia de SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA nao criada. ';
    END
    IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_DEV34') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA')), N'SP_FIKON_INTEGRA_MOV_ITSAIDA', N'SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_DEV34');
        EXEC sys.sp_executesql @def;
        IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_MOV_ITSAIDA_BKP_DEV34') IS NULL SET @erro = @erro + 'copia de SP_FIKON_INTEGRA_MOV_ITSAIDA nao criada. ';
    END
    IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_DEV34') IS NULL
    BEGIN
        SET @def = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO')), N'SP_FIKON_ATUALIZA_STATUS_PEDIDO', N'SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_DEV34');
        EXEC sys.sp_executesql @def;
        IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_STATUS_PEDIDO_BKP_DEV34') IS NULL SET @erro = @erro + 'copia de SP_FIKON_ATUALIZA_STATUS_PEDIDO nao criada. ';
    END
END

IF @erro <> ''
BEGIN
    RAISERROR('Nada foi alterado: %s', 16, 1, @erro);
    SET NOEXEC ON;
END
ELSE
    PRINT 'Versoes conferidas e copias guardadas (<nome>_BKP_DEV34).';
GO

/* ===================== 2. Tabela FIKON_CAD_CAIXA (igual à produção) ===================== */
IF OBJECT_ID('dbo.FIKON_CAD_CAIXA') IS NULL
BEGIN
    CREATE TABLE dbo.FIKON_CAD_CAIXA (
        ID      int IDENTITY(1,1) NOT NULL,
        CODFIL  int NULL,
        SERIE   varchar(3) NULL,
        CAIXA   int NULL,
        CODOPER int NULL
    );
    PRINT 'FIKON_CAD_CAIXA criada.';
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.FIKON_CAD_CAIXA WHERE CODFIL = 15 AND SERIE = 'U05')
    INSERT INTO dbo.FIKON_CAD_CAIXA (CODFIL, SERIE, CAIXA, CODOPER) VALUES (15, 'U05', 4, 24);
IF NOT EXISTS (SELECT 1 FROM dbo.FIKON_CAD_CAIXA WHERE CODFIL = 15 AND SERIE = 'U06')
    INSERT INTO dbo.FIKON_CAD_CAIXA (CODFIL, SERIE, CAIXA, CODOPER) VALUES (15, 'U06', 3, 24);
GO

/* ===================== 3. De-para de bandeiras: variações "Débito"/"Crédito" (script 31) ===================== */
DECLARE @novas TABLE (BANDEIRA_FIKON varchar(40), TIPO char(1), BASE varchar(40), CODCON_PADRAO int, OBS varchar(100));
INSERT INTO @novas VALUES
    ('ELO DEBITO',         'D', 'ELO',        29, 'Elo debito (nome com o tipo)'),
    ('ELO CREDITO',        'C', 'ELO',        30, 'Elo credito (nome com o tipo)'),
    ('VISA DEBITO',        'D', 'VISA',       11, 'Visa debito (nome com o tipo)'),
    ('VISA CREDITO',       'C', 'VISA',        2, 'Visa credito (nome com o tipo)'),
    ('MASTERCARD CREDITO', 'C', 'MASTERCARD',  1, 'Mastercard credito (nome com o tipo)'),
    ('MASTER DEBITO',      'D', 'MASTERCARD', 10, 'Mastercard debito (nome com o tipo)'),
    ('MASTER CREDITO',     'C', 'MASTERCARD',  1, 'Mastercard credito (nome com o tipo)');

INSERT INTO dbgemco.dbo.FIKON_DEPARA_BANDEIRA (BANDEIRA_FIKON, TIPO, CODCON, OBS)
SELECT n.BANDEIRA_FIKON, n.TIPO, ISNULL(b.CODCON, n.CODCON_PADRAO), n.OBS
  FROM @novas n
  OUTER APPLY (SELECT TOP (1) x.CODCON FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA x
                WHERE x.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI = n.BASE COLLATE Latin1_General_CI_AI
                  AND x.TIPO = n.TIPO AND x.ATIVO = 1 ORDER BY x.ID) b
 WHERE NOT EXISTS (SELECT 1 FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA x
                    WHERE x.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI = n.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI AND x.TIPO = n.TIPO)
   AND EXISTS (SELECT 1 FROM dbgemco..CXA_CADCON c WHERE c.CODCON = ISNULL(b.CODCON, n.CODCON_PADRAO));
PRINT CONCAT(@@ROWCOUNT, ' variacao(oes) de bandeira incluida(s).');
GO

/* ===================== 4. Procedures (texto da produção) ===================== */
/* ===================== SP_FIKON_CANCELAR_NOTA (versão da produção: scripts 20, 23 e 27) ===================== */
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

/* ===================== SP_FIKON_NOTA_GRAVAR_FINANCEIRO (versão da produção: scripts 21) ===================== */
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

/* ===================== SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO (versão da produção: scripts 24) ===================== */
ALTER proc [dbo].[SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO]
 @chavenfe varchar(44)

 as

-- script 24 (18/11/2026): a nota de saida vem da ENT_NOTASAI pela chave completa da devolucao e com a SERIE DA
-- VENDA (SERIESAI). Antes lia a coluna SERIE (serie da devolucao): o OBSFISCAL saia "SERIE: 2" e o status da
-- venda nao era atualizado (venda devolvida por inteiro ficava 7 em vez de 8). O total dos itens tambem passa
-- a filtrar remetente e serie, e o VALOR do OBSFISCAL e o total da venda, como nas devolucoes do Gemco.

 declare @numnota numeric(12,0)
 declare @codfil int
 declare @tpnota varchar(3)
 declare @dtnota date
 declare @vltotal numeric(15,2)
 declare @serie varchar(3)
 declare @codremet numeric(12,0)
 declare @status int
 declare @codfilsai int
 declare @numnotasai numeric(15,0)
 declare @seriesai varchar(3)
 declare @tpnotasai varchar(3)
 declare @dtnotasai date
 declare @vlvenda numeric(15,2)


 select @numnota = numnota, @codfil = codfil, @tpnota = TPNOTA, @dtnota = dtnota, @serie = serie, @codremet = CODREMET
   from ent_nota
  where chavenfe = @chavenfe and TPNOTA = 26

 if @numnota is null
 begin
    raiserror('SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO: devolucao com a chave %s nao encontrada na ENT_NOTA.', 16, 1, @chavenfe)
    return
 end

 select @vltotal = sum(VLTOTAL)
   from ENT_ITENT
  where CODFIL = @codfil and TPNOTA = @tpnota and CODREMET = @codremet and SERIE = @serie
    and DTNOTA = @dtnota and NUMNOTA = @numnota

 select @numnotasai = NUMNOTASAI, @seriesai = SERIESAI, @tpnotasai = TPNOTASAI, @codfilsai = CODFILSAI, @dtnotasai = DTNOTASAI
   from ENT_NOTASAI
  where CODFIL = @codfil and TPNOTA = @tpnota and CODREMET = @codremet and SERIE = @serie
    and DTNOTA = @dtnota and NUMNOTA = @numnota

 select @vlvenda = VLTOTAL
   from MOV_SAIDA
  where CODFIL = @codfilsai and TPNOTA = @tpnotasai and NUMNOTA = @numnotasai and SERIE = @seriesai and DTNOTA = @dtnotasai

 update ENT_NOTA
    set VLTOTAL = @vltotal,
        OBSFISCAL = 'NF: ' + CONVERT(varchar, @numnotasai) + ' SERIE: ' + @seriesai + ' DT: ' + CONVERT(varchar, @dtnotasai, 103)
                  + ' VALOR: ' + replace(convert(varchar, isnull(@vlvenda, @vltotal)), '.', ',')
  where CHAVENFE = @chavenfe and TPNOTA = 26

 if (SELECT sum(QTCOMP) - sum(isnull(QTDEVOL, 0)) FROM MOV_ITSAIDA WHERE CODFIL = @codfilsai AND TPNOTA = @tpnotasai AND NUMNOTA = @numnotasai AND SERIE = @seriesai AND DTNOTA = @dtnotasai) > 0
    set @status = 7
 else
    set @status = 8

 UPDATE MOV_SAIDA WITH (READCOMMITTED) SET STATUS = @status
  WHERE CODFIL = @codfilsai AND TPNOTA = @tpnotasai AND NUMNOTA = @numnotasai AND SERIE = @seriesai AND DTNOTA = @dtnotasai
GO

/* ===================== SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA (versão da produção: scripts 29) ===================== */
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

/* ===================== SP_FIKON_INTEGRA_MOV_ITSAIDA (versão da produção: scripts 32) ===================== */
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

/* ===================== SP_FIKON_ATUALIZA_STATUS_PEDIDO (versão da produção: scripts 33) ===================== */
ALTER PROC [dbo].[SP_FIKON_ATUALIZA_STATUS_PEDIDO]  

-- TIPO
-- D Debito
-- C Credito
-- P Pix Maquina Rede
-- F Pix FixPay

@NUMPEDVEN NUMERIC(12,0),
@CODFIL int,
@documento varchar(20),
@bandeira varchar(20),
@tipo varchar(1),
@serie varchar(3) = NULL   -- script 33: serie da nota no Gemco (ex.: U05), quando o Integrador ja souber

AS

-- script 33 (24/11/2026): caixa e operador do lancamento pela dbgemco.dbo.FIKON_CAD_CAIXA (filial + serie; sem serie
-- ou sem linha da serie, a primeira linha da filial). Caixa/operador 'CARTOES' so quando a filial nao tem nenhuma
-- linha na FIKON_CAD_CAIXA (comportamento anterior).

DECLARE @coditprod numeric(9,0)
DECLARE @filorig int
DECLARE @qtcomp numeric(9,4)
DECLARE @tpdepos varchar(1) ='N'
DECLARE @tpdepostransf varchar(1) ='N'
DECLARE @codfiltransf int
DECLARE @fllotevencto varchar(1)
DECLARE @lote varchar(20)
DECLARE @encomenda varchar(1)
DECLARE @numpedtransf numeric(9,0)
DECLARE @coduser numeric(9,0) = 508
DECLARE @codoper int
DECLARE @numcxa int
DECLARE @taxadm numeric(9,2)
DECLARE @codcon int
DECLARE @qtprc int


-- script 33: caixa/operador da FIKON_CAD_CAIXA (a linha da serie primeiro; senao a primeira da filial)
SELECT TOP (1) @numcxa = c.CAIXA, @codoper = c.CODOPER
  FROM dbgemco.dbo.FIKON_CAD_CAIXA c
 WHERE c.CODFIL = @CODFIL AND c.CAIXA IS NOT NULL AND c.CODOPER IS NOT NULL
 ORDER BY CASE WHEN @serie IS NOT NULL AND c.SERIE = LTRIM(RTRIM(@serie)) THEN 0 ELSE 1 END, c.ID

-- filial sem nenhuma linha na FIKON_CAD_CAIXA: caixa/operador 'CARTOES' (como antes)
IF @numcxa IS NULL
BEGIN
    SET @numcxa = (SELECT NUMCXA FROM dbgemco..CXA_CAIXAS WHERE CODFIL=@CODFIL AND DESCXA LIKE '%CARTOES')

    SET @codoper = (SELECT CODOPER FROM dbgemco..CXA_OPERADOR WHERE CODFIL=@CODFIL AND NOME LIKE '%CARTOES')
END


IF(@documento = '')
    SET @documento = null


DECLARE CR_UPDATE CURSOR FOR
SELECT itp.coditprod, itp.FILORIG, itp.qtcomp*-1, itp.tpdepos, itp.CODFILTRANSF, isnull(FLLOTEVENCTO,'N'), isnull(FLVDANTEC,'N'), itf.numpedtransf 
FROM dbgemco..mov_itped itp 
LEFT JOIN dbgemco..mov_itpedtransf itf on itp.numpedven=itf.numpedven and itp.coditprod=itf.CODITPROD and itp.codfiltransf=itf.CODFILTRANSF and isnull(itf.status,0)<9
WHERE itp.NUMPEDVEN=@NUMPEDVEN
GROUP BY itp.coditprod, itp.FILORIG, itp.qtcomp*-1, itp.tpdepos, itp.CODFILTRANSF, isnull(FLLOTEVENCTO,'N'), isnull(FLVDANTEC,'N'), itf.numpedtransf

OPEN CR_UPDATE
FETCH NEXT FROM CR_UPDATE INTO @coditprod, @filorig, @qtcomp, @tpdepos, @codfiltransf, @fllotevencto, @encomenda, @numpedtransf
WHILE @@FETCH_STATUS = 0
BEGIN

    UPDATE dbgemco..mov_pedido SET fllibfat='S' WHERE NUMPEDVEN=@numpedtransf
    UPDATE dbgemco..mov_itped SET fllibfat='S' WHERE NUMPEDVEN=@numpedtransf

    FETCH NEXT FROM CR_UPDATE INTO @coditprod, @filorig, @qtcomp, @tpdepos, @codfiltransf, @fllotevencto, @encomenda, @numpedtransf
END

CLOSE CR_UPDATE
DEALLOCATE CR_UPDATE 

-- Busca quantidade de parcelas com segurança
SET @qtprc = (SELECT max(numprc) FROM dbgemco..cxa_lancto WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN)
SET @qtprc = ISNULL(@qtprc, 1)

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


IF(@tipo='P')
BEGIN
    UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2, NUMDOC = @documento, TAXADM=0.95, CODPORT = 52, CODCON=49, forma='139', codeve=139 WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN and codeve=139
END

IF(@tipo='F')
BEGIN
    UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2, NUMDOC = @documento, TAXADM=1.19, CODPORT = 59, CODCON=327, forma='142', codeve=142 WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN
END


IF(@tipo not in ('P','F'))  
BEGIN
   if(select min(codeve) from cxa_lancto where TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN ) not in (5, 145)
   begin
    UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
    UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2, NUMDOC = @documento, TAXADM=@taxadm, CODCON=@codcon WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN and codeve not in (139)
	end
	  else
	     begin
		   UPDATE DBGEMCO..MOV_PEDIDO SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
           UPDATE DBGEMCO..MOV_ITPED SET status=5 WHERE NUMPEDVEN = @NUMPEDVEN
           UPDATE DBGEMCO..CXA_LANCTO SET codfilcxa=@CODFIL, numcxa=@numcxa, nummov=1, codoper=@codoper, status=2  WHERE TRY_CAST(numped AS numeric(12,0)) = @NUMPEDVEN and codeve not in (139)
		 end
END


-----------------------------------------------------------------------------------------
--  Atualiza a tabela de controle Fikon/Gemco
-----------------------------------------------------------------------------------------
UPDATE [dbgemco].[dbo].[FIKON_INTEGRACAO_PEDIDO]
SET [STATUS] = 'LIBERADO CXA'
WHERE [pedido_gemco] = @NUMPEDVEN
GO


SET NOEXEC OFF;
GO

/* ===================== 5. Conferência ===================== */
SELECT v.nome, o.modify_date,
       CASE WHEN CHARINDEX(v.marca, OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END AS atualizada,
       CASE WHEN OBJECT_ID('dbo.' + v.nome + '_BKP_DEV34') IS NOT NULL THEN 'SIM' ELSE 'NAO' END AS copia
  FROM (VALUES ('SP_FIKON_CANCELAR_NOTA', 'script 27'),
              ('SP_FIKON_NOTA_GRAVAR_FINANCEIRO', 'script 21'),
              ('SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO', 'script 24'),
              ('SP_FIKON_INTEGRA_CUPOM_MOV_SAIDA', 'script 29'),
              ('SP_FIKON_INTEGRA_MOV_ITSAIDA', 'script 32'),
              ('SP_FIKON_ATUALIZA_STATUS_PEDIDO', 'script 33')) v(nome, marca)
  LEFT JOIN sys.objects o ON o.name = v.nome
 ORDER BY v.nome;
SELECT * FROM dbo.FIKON_CAD_CAIXA ORDER BY CODFIL, ID;
GO
