/*
  10 - NF de transferência FIKON -> Gemco  -  11/11/2026

  Evento TRANSFERENCIA do webhook da FIKON (ApiAcal: FikonController -> PedidoFikonRepositprio
  .integrarTransferenciaGemco -> ProcessarConsultaTransferenciaAsync). A NF-e de transferência é
  emitida pela FIKON; o Gemco registra o pedido de transferência e a nota já faturada, com o número,
  a série e a chave que a FIKON autorizou.

  Procedures (chamadas pelo ApiAcal numa única transação; nenhuma delas abre transação):
    1. dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA    -> pedido (MOV_PEDIDO) e nota (MOV_SAIDA)
    2. dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA  -> cada item: MOV_ITPED, MOV_ITSAIDA, estoque,
                                                         lote e totais do pedido e da nota

  Base: logs do Gemco (G2000SQL_gerando_pedido.LOG, pedido 13296780 com produto de lote;
  G2000SQL_faturando.LOG, pedido 13294264 / nota 374825) e as transferências nativas (TPNOTA 144)
  do dbgemco de DEV.

  PEDIDO (o Gemco cria o pedido e depois fatura; aqui os dois são gravados já no estado faturado)
    - Número: tabela SEQPED (mesma regra da SP_SEQPED, sem chamar a procedure: ela abre transação
      própria).
    - MOV_PEDIDO na filial de origem (99% dos pedidos de transferência nativos): CODFIL = FILORIG =
      origem, CODCLI = destino, TIPOPED 2, TPPED 'E', TPNOTA 144, STATUS 6 e SITCARGA 3 (faturado),
      PRACA da filial de destino, LOCAL da CAD_DEPOS da origem. A MOV_PEDIDO_COMPL é criada pelo
      trigger MOV_PEDIDO_TR_INS.
    - MOV_ITPED: STATUS 6, QTEMITIDO = QTFAT = QTORIG = quantidade, QTLIB 0, NUMNOTA/DTNOTA da nota,
      FLATUTRAN 'S', FLLIBFAT 'S', TPPED 'E'.

  NOTA
    - MOV_SAIDA TPNOTA 144, TIPOPED 2, NUMPEDVEN do pedido, FILPED = origem, CODCLI = destino,
      modelo 55, STATUS 2 e STATUSNFE 2 (nota já autorizada pela FIKON: com STATUS 6 e STATUSNFE 0 o
      trigger REPLICA_NFE_GEMCO_SAIDA mandaria a nota para o emissor do Gemco).
      Natureza: CODNATOP/CODNATOPCOMPL 515/2 se houver item sem ST; CODNATOPDIF/CODNATOPDIFCOMPL
      540/9 se houver item com ST (CTF 60).
    - O número da nota é o da FIKON: não mexe na CAD_FILIAL_COMPL.SEQNOTAVEN7.
    - PREÇO (alterado em 12/11/2026): preço do item = CMUP da VEN_PRODFIL da filial 8, arredondado em
      2 casas (como o Gemco grava na transferência); total do item = quantidade x preço. O preço e o
      total que vêm da FIKON não são usados. Produto sem CMUP na filial 8: erro, nada é gravado.
      Os totais da nota e do pedido são a soma dos itens.
    - MOV_ITSAIDA: CODCLI = destino, FLATUTRAN 'P', CMUP/CUE da VEN_PRODFIL da filial 8,
      TPDEPOS e LOCAL da CAD_DEPOS da origem ('L' quando houver).
    - ICMS por CTF (CAD_IMPTRIBUT com o CODGRPTPNOTA do TPNOTA 144; T = total do item, U = T/Q,
      A = ALIQICM, R = ALIQICMRED, trunc = truncar em 2 casas). Conferido nos itens nativos:
      | CTF | Totais do item                                    | Unitários (9 casas)                 | Nat. |
      |-----|---------------------------------------------------|-------------------------------------|------|
      | 0   | VLBASEICMS = T; VLICM = trunc(T*A/100)            | VLBASEICMSF = U; VLICMF = U*A/100   | 515/2|
      | 20  | VLBASEICMS = round(T*(100-R)/100, 2);             | VLBASEICMSF = U*(100-R)/100;        | 515/2|
      |     | VLNTRIBUT = T - VLBASEICMS;                       | VLICMF = VLBASEICMSF*A/100;         |      |
      |     | VLICM = trunc(VLBASEICMS*A/100)                   | VLNTRIBUTF = U*R/100                |      |
      | 40  | VLISENTO = T                                      | VLISENTOF = U                       | 515/2|
      | 60  | VLOUTRAS = T; ICMS próprio 0; efetivo 0           | VLOUTRASF = U; VLICMOPERSTF = U*A/100| 540/9|
      ALIQICMUF = ALIQICM; ALIQICMSUBUF = ALIQICM no CTF 60, senão 0; ORIGEMPROD = CAD_PROD.ORIGEM.
      Outros CTF (10, 90...): erro e nada é gravado.
    - CBS/IBS: CAD_IMPTRIBUT_REFORMA com o grupo do TPNOTA 144; PIS/COFINS pelo trigger da MOV_ITSAIDA.
    - Fila de NF-e: o trigger REPLICA_NFE_SAIDA põe o item na INT_NFE_SAIDA quando a série é a série 7
      da filial; a procedure apaga essa linha na mesma transação (a NF-e já foi emitida pela FIKON).
    - O trigger MOV_ITSAIDA_TR_INS só gera entrada automática no destino com FLPEDTRANSFLOG = 'S'
      (não usado aqui).

  ESTOQUE (mesma sequência do Gemco, registrada na MOV_EXTRATOPROD)
    Pedido (MODULO 1, rotina GRAVAITENSPED): destino TRANSITO + q; origem RESFIS + q.
    Nota   (MODULO 3, rotina GRAVAITENSNOTAFISCAL): origem FISICO - q e RESFIS - q.
    Resultado: origem FISICO - q; destino TRANSITO + q até a entrada.

  LOTE (só para produto com CAD_PROD.FLLOTEVENCTO = 'S'; nos demais, nada de lote é feito)
    - Os lotes vêm no parâmetro @lotes do item, no formato 'LOTE:QTD|LOTE:QTD' (QTD com ponto).
      A soma tem de ser igual à quantidade do item, e cada lote precisa de saldo na origem
      (MOV_LOTEVENCTO: QTDE - RESFIS).
    - MOV_LOTEVENCTO_NF na origem, já no estado faturado (como as linhas nativas depois da nota):
      NUMNOTA/SERIE/DTNOTA da nota, QTDE = q, RESFIS 0, STATUS 6, QTLIB 0, QTORIG = q, ITPEDITEM = item.
    - MOV_LOTEVENCTO da origem: QTDE - q (o pedido soma RESFIS + q; a nota tira QTDE - q e RESFIS - q,
      conforme G2000SQL_faturando2.LOG, pedido 13296780 / nota 374826). Lote que fica com
      QTDE + BLOQUEADO = 0 é apagado da MOV_LOTEVENCTO, como o Gemco faz.

  Duplicidade: nota com a mesma chave já na MOV_SAIDA não é gravada; o ApiAcal responde sucesso quando
  a transferência com essa chave já está no Gemco.

  Fora deste script: entrada na filial de destino (ENT_NOTA/ENT_ITENT).

  Como rodar: no SSMS, no servidor certo e no banco dbgemco, executar o script INTEIRO (F5).
  Só cria/altera as duas procedures; não altera dados.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA') IS NULL
    EXEC ('CREATE PROC dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA AS RETURN 0');
GO

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA') IS NULL
    EXEC ('CREATE PROC dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA AS RETURN 0');
GO

/* ===================== 1. Pedido e cabeçalho da nota ===================== */
ALTER PROC dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA
    @numnota                 numeric(9,0),
    @serie                   varchar(3),
    @chave                   varchar(44),
    @dtemissao               datetime,        -- data e hora de emissão da NF-e na FIKON
    @vltotal                 numeric(15,2),
    @estabelecimento         numeric(15,0),   -- estabelecimento FIKON de origem
    @estabelecimento_destino numeric(15,0),   -- estabelecimento FIKON de destino
    @chcriacao               varchar(20),
    @obs                     varchar(255)
AS
-- Criada em 11/11/2026 (script 10_transferencia_FIKON.sql). Ver o cabeçalho do script.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @codfil        numeric(5,0)
DECLARE @codfil_dest   numeric(5,0)
DECLARE @estado        char(2)
DECLARE @praca_dest    numeric(5,0)
DECLARE @local         numeric(2,0)
DECLARE @dtnota        date
DECLARE @tpnota        numeric(3,0) = 144
DECLARE @numpedven     numeric(12,0)
DECLARE @coduser       numeric(6,0) = 537
DECLARE @identproc     varchar(250)
DECLARE @datahorautc   varchar(25)
DECLARE @msg           varchar(400)
DECLARE @estab_txt     varchar(20)

SET @chave = LTRIM(RTRIM(ISNULL(@chave, '')))
SET @serie = LTRIM(RTRIM(ISNULL(@serie, '')))

IF LEN(@chave) <> 44 OR @chave LIKE '%[^0-9]%'
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA: chave de acesso invalida (%s).', 16, 1, @chave);
    RETURN;
END

IF ISNULL(@numnota, 0) <= 0 OR LEN(@serie) = 0 OR @dtemissao IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA: numero, serie e data de emissao sao obrigatorios (chave %s).', 16, 1, @chave);
    RETURN;
END

-- TRAVA_CHAVE_DUPLICADA: não grava nota cuja chave já existe na MOV_SAIDA (ativa ou cancelada).
IF EXISTS (SELECT 1 FROM dbo.MOV_SAIDA WHERE CHAVENFE = @chave)
BEGIN
    SET @msg = 'Nota com chave ' + @chave
             + ' ja existe na MOV_SAIDA (ativa ou cancelada): gravacao recusada para evitar duplicidade.';
    RAISERROR(@msg, 16, 1);
    RETURN;
END

-- De-para estabelecimento FIKON -> filial Gemco
SELECT TOP (1) @codfil = filial_genco FROM dbo.FIKON_VINCULO_FILIAL WHERE filial_fikon = @estabelecimento
SELECT TOP (1) @codfil_dest = filial_genco FROM dbo.FIKON_VINCULO_FILIAL WHERE filial_fikon = @estabelecimento_destino

IF @codfil IS NULL OR @codfil_dest IS NULL
BEGIN
    SET @estab_txt = CONVERT(varchar(20), CASE WHEN @codfil IS NULL THEN @estabelecimento ELSE @estabelecimento_destino END)
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA: estabelecimento FIKON %s sem vinculo na FIKON_VINCULO_FILIAL.', 16, 1, @estab_txt);
    RETURN;
END

IF @codfil = @codfil_dest
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA: filial de origem e de destino sao a mesma (chave %s).', 16, 1, @chave);
    RETURN;
END

SELECT @estado = ESTADO FROM dbo.CAD_FILIAL WHERE CODFIL = @codfil
SELECT @praca_dest = PRACA FROM dbo.CAD_FILIAL WHERE CODFIL = @codfil_dest

SELECT TOP (1) @local = LOCAL
  FROM dbo.CAD_DEPOS
 WHERE CODFIL = @codfil
 ORDER BY CASE TPDEPOS WHEN 'L' THEN 0 ELSE 1 END

SET @dtnota      = CAST(@dtemissao AS date)
SET @datahorautc = CONVERT(varchar(19), @dtemissao, 126) + '-03:00'
SET @identproc   = 'INTEGRADOR FIKON - TRANSFERENCIA - CHCRIACAO ' + ISNULL(@chcriacao, '')
SET @obs         = NULLIF(LTRIM(RTRIM(ISNULL(@obs, ''))), '')

IF @obs IS NULL
    SET @obs = 'TRANSFERENCIA FIKON NF ' + CONVERT(varchar(12), @numnota) + ' PARA FILIAL ' + CONVERT(varchar(5), @codfil_dest)

-- Número do pedido: mesma tabela e regra da SP_SEQPED (atualização atômica)
UPDATE dbo.SEQPED WITH (READCOMMITTED)
   SET @numpedven = LAST_NUMBER = LAST_NUMBER + 1

IF @numpedven IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA: nao foi possivel gerar o numero do pedido (SEQPED).', 16, 1);
    RETURN;
END

/* ---------- Pedido de transferência, já faturado ---------- */
-- Totais recalculados a cada item (SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA).
INSERT INTO dbo.MOV_PEDIDO (
    CODFIL, TIPOPED, NUMPEDVEN, TPPED, FILORIG, LOCAL, CODCLI, DTPEDIDO, DTENTREGA, PRACA,
    VLMERCAD, VLTOTAL, VLVDVISTA, VLTOTITEMACUM, SITCARGA, STATUS, TPNOTA, HRPEDIDO, TPFRETE,
    FLLIBFAT, DTLIBFAT, CODUSER, OBS, TPCONTRATO, SERIECONTRAFIN, REGRACREDITSCORE, IDENTPROC,
    CODFILTRANSFFAT, FLFATPARCIAL, TPPGTO, FLGERACRED,
    -- 0 / 'N' como o Gemco grava (evita NULL em somas e ligações das telas)
    ENDCOB, ENDENT, ENDFAT, CODTRANSP, VLDESCONTO, VLFRETE, VLENTRADA, VLDESPACES, VLOUTDESP, VLDESPFIN,
    VLSEGURO, FLSEGURO, INTEGRACRC
) VALUES (
    @codfil, 2, @numpedven, 'E', @codfil, @local, @codfil_dest, @dtnota, DATEADD(day, 2, @dtnota), @praca_dest,
    @vltotal, @vltotal, @vltotal, @vltotal, 3, 6, @tpnota, CONVERT(datetime, CONVERT(varchar(8), @dtemissao, 108), 108), 3,
    'S', @dtnota, @coduser, @obs, 'C', '0', '0', @identproc,
    @codfil, 'S', 1, 'N',
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 'N', 'N'
);

/* ---------- Cabeçalho da nota ---------- */
-- Valores fiscais, peso e natureza recalculados a cada item. Fixos conforme as notas 144 nativas.
INSERT INTO dbo.MOV_SAIDA (
    CODFIL, TPNOTA, NUMNOTA, SERIE, DTNOTA, TIPOPED, DTEMISSAO, DTPEDIDO, DTENTREGA, ESTADO,
    NUMPEDVEN, CODCLI, CODVENDR, ENDCOB, ENDENT, ENDFAT, LOCAL, PESO, PESOLIQ, PRACA, AUTORIZAC,
    VLDESPACES, VLBASEICMS, VLDESCONTO, VLDESPFIN, VLFRETE, VLICM, VLICMRET, VLIPI, VLMERCAD,
    VLOUTDESP, VLSEGURO, VLENTRADA, CUBAGNF, STATUS, FILPED, VLISENTO, VLOUTRAS, VLBASEIPI,
    VLTOTAL, VLBASEICMSSUB, VLISS, VLVDLIQ, HRHORA, TPFRETE, FLNFMANUAL, VLJUROSFIN, PJUROS,
    DTATUEST, FLATUEST, CONTROLE, CODUSER, VLAGREGACRC, VLISENTOIPI, VLOUTRASIPI, QTPRC, VLPRC,
    OBS, IDENTPROC, DATENT, VLFRETETERCEIRO, SERIECONTRAFIN, TPCONTRATO, VLJUROS, VLDESCPRESUMIDOV,
    VLBASEICMD, VLICMD, VLPISCOFINSCSLL, INTEGRACRC, FLDEVOL, FLSEMSERIE, FLSEGURO, FLNOTASERVICO,
    VLBASEICMORIGREPI, VLICMORIGREPI, VLICMREPI, VLDESCNOTA, TPPGTO, VLTOTALSIMPFAT, VLICMDESCONTO,
    VLICMTRANSF, VLTAC, VLTARBANCARIA, VLCOFDESCONTO, VLPISDESCONTO, VLBASEICMSDIFSAI, VLICMDIFSAI,
    STATUSNFE, CHAVENFE, VLICMCREDITO, VLICMRETV, VLNTRIBUTD, VLTOTCOFINSRET, VLTOTCSLLRET,
    VLTOTIRRET, VLTOTPISRET, LOTE, VLDESCPRESUMIDOF, VLIRRF, DATAHORAUTC, CODCONTR, VLFECEP,
    VLFECEPST, VLICMPART, VLICMPARTUF, MODELONF, FLEXCFCPBCPISCOFINS, FLEXCICMSBCPISCOFINS,
    CODPROFISSAOCASHBACK, CODNATOP, CODNATOPCOMPL, CODNATOPDIF, CODNATOPDIFCOMPL
) VALUES (
    @codfil, @tpnota, @numnota, @serie, @dtnota, 2, @dtnota, @dtnota, DATEADD(day, 2, @dtnota), @estado,
    @numpedven, @codfil_dest, 0, 0, 0, 0, @local, 0, 0, @praca_dest, '0',
    0, 0, 0, 0, 0, 0, 0, 0, @vltotal,
    0, 0, 0, 0, 2, @codfil, 0, 0, 0,
    @vltotal, 0, 0, 0, @dtemissao, 3, 'N', 0, 0,
    GETDATE(), 'S', 'AC12', @coduser, 0, 0, 0, 0, 0,
    @obs, @identproc, @dtnota, 0, '0', 'C', 0, 0,
    0, 0, 0, 'N', 'N', 'N', 'N', 'N',
    0, 0, 0, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    2, @chave, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, @datahorautc, 0, 0,
    0, 0, 0, '55', 'N', 'S',
    0, NULL, NULL, 0, 0
);
GO

/* ===================== 2. Itens ===================== */
ALTER PROC dbo.SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA
    @chavenfe   varchar(44),
    @codigo     varchar(20),            -- código do produto na FIKON (CODITPROD + dígito verificador)
    @qtcomp     numeric(9,3),
    @precounit  numeric(17,4),          -- preço da FIKON: substituído pelo custo da VEN_PRODFIL (filial 8)
    @vltotal    numeric(15,2),          -- total da FIKON: recalculado (quantidade x custo)
    @lotes      varchar(4000) = NULL    -- 'LOTE:QTD|LOTE:QTD' (só para produto com controle de lote)
AS
-- Criada em 11/11/2026 (script 10_transferencia_FIKON.sql). Ver o cabeçalho do script.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coditprod      numeric(10,0)
DECLARE @prod_txt       varchar(20)
DECLARE @ctf_txt        varchar(10)
DECLARE @codfil         numeric(5,0)
DECLARE @codfil_dest    numeric(5,0)
DECLARE @codfilcust     numeric(5,0)
DECLARE @tpnota         numeric(3,0)
DECLARE @numnota        numeric(9,0)
DECLARE @serie          varchar(3)
DECLARE @dtnota         datetime
DECLARE @hrhora         datetime
DECLARE @numpedven      numeric(12,0)
DECLARE @item           numeric(4,0)
DECLARE @achou          int
DECLARE @msg            varchar(400)
DECLARE @coduser        numeric(6,0) = 537
DECLARE @identproc      varchar(250) = 'INTEGRADOR FIKON - TRANSFERENCIA'

-- Cadastro do produto
DECLARE @codprod        numeric(10,0)
DECLARE @codicms        numeric(4,0)
DECLARE @codicmred      numeric(4,0)
DECLARE @codicmsub      numeric(4,0)
DECLARE @ncm            varchar(8)
DECLARE @origem         numeric(2,0)
DECLARE @codcbs         numeric(4,0)
DECLARE @codibs         numeric(4,0)
DECLARE @pesounit       numeric(12,3)
DECLARE @fllote         char(1)
DECLARE @unembal        varchar(2)
DECLARE @codbarra       numeric(14,0)
DECLARE @codsitprod     varchar(2)
DECLARE @cmup           numeric(15,4)
DECLARE @cmupi          numeric(15,4)
DECLARE @cue            numeric(17,4)
DECLARE @cest           varchar(7)

-- Estoque
DECLARE @tpdepos        char(1)
DECLARE @local          numeric(2,0)
DECLARE @fisico         numeric(9,3)
DECLARE @resfis         numeric(9,3)
DECLARE @status_loc     numeric(1,0)
DECLARE @tpdepos_dest   char(1)
DECLARE @transito_dest  numeric(9,3)
DECLARE @status_dest    numeric(1,0)
DECLARE @qtbaixa        numeric(9,3)

-- Lotes
DECLARE @tl TABLE (LOTEVENCTO varchar(20) NOT NULL, QTDE numeric(9,3) NOT NULL)
DECLARE @resto          varchar(4000)
DECLARE @par            varchar(200)
DECLARE @pos            int
DECLARE @lote           varchar(20)
DECLARE @qtlote_txt     varchar(50)
DECLARE @qtlote         numeric(9,3)
DECLARE @somalotes      numeric(9,3)
DECLARE @qtde_lote      numeric(9,3)
DECLARE @resfis_lote    numeric(9,3)

-- ICMS
DECLARE @uf             char(2)
DECLARE @codgrptpnota   numeric(3,0)
DECLARE @ctf            numeric(2,0)
DECLARE @ctf_i          numeric(2,0)
DECLARE @ctf_r          numeric(2,0)
DECLARE @ctf_s          numeric(2,0)
DECLARE @aliqicm        numeric(7,4) = 0
DECLARE @aliqicmred     numeric(7,4) = 0
DECLARE @aliqicmsub     numeric(7,4) = 0
DECLARE @aliqicmsubuf   numeric(7,4) = 0
DECLARE @obs_i          varchar(180)
DECLARE @obs_r          varchar(180)
DECLARE @obs_s          varchar(180)
DECLARE @obsfiscal      varchar(180)
DECLARE @codnatop       numeric(3,0)
DECLARE @codnatopcompl  numeric(2,0)

DECLARE @U              numeric(28,15)
DECLARE @vlbaseicm      numeric(15,2) = 0
DECLARE @vlicm          numeric(15,2) = 0
DECLARE @vlisento       numeric(15,2) = 0
DECLARE @vlntribut      numeric(15,2) = 0
DECLARE @vloutras       numeric(15,2) = 0
DECLARE @vlbaseicmsf    numeric(22,9) = 0
DECLARE @vlicmf         numeric(22,9) = 0
DECLARE @vlisentof      numeric(22,9) = 0
DECLARE @vlntributf     numeric(22,9) = 0
DECLARE @vloutrasf      numeric(22,9) = 0
DECLARE @vlicmoperstf   numeric(20,9) = 0

-- CBS / IBS
DECLARE @aliqcbs        numeric(7,4) = 0
DECLARE @aliqibs        numeric(7,4) = 0
DECLARE @aliqibsmun     numeric(7,4) = 0
DECLARE @cstcbs         varchar(4) = NULL
DECLARE @cstibs         varchar(4) = NULL
DECLARE @clastribcbs    varchar(10) = NULL
DECLARE @clastribibs    varchar(10) = NULL
DECLARE @vlbasecbs      numeric(20,9) = 0
DECLARE @vlcbs          numeric(20,9) = 0
DECLARE @vlbaseibs      numeric(20,9) = 0
DECLARE @vlibs          numeric(20,9) = 0
DECLARE @vlbaseibsmun   numeric(20,9) = 0
DECLARE @vlibsmun       numeric(20,9) = 0

/* ---------- Validações ---------- */
SET @chavenfe = LTRIM(RTRIM(ISNULL(@chavenfe, '')))
SET @codigo   = LTRIM(RTRIM(ISNULL(@codigo, '')))

-- O código da FIKON traz o dígito verificador no fim (mesma regra do cupom): CODITPROD = código sem o último dígito.
IF LEN(@codigo) < 2 OR LEN(@codigo) > 11 OR @codigo LIKE '%[^0-9]%'
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: codigo de produto FIKON invalido (%s).', 16, 1, @codigo);
    RETURN;
END

SET @coditprod = CAST(LEFT(@codigo, LEN(@codigo) - 1) AS numeric(10,0))
SET @prod_txt  = CONVERT(varchar(20), @coditprod)

IF ISNULL(@qtcomp, 0) <= 0 OR ISNULL(@vltotal, -1) < 0
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: quantidade ou valor invalido para o produto %s.', 16, 1, @prod_txt);
    RETURN;
END

SELECT @codfil = CODFIL, @codfil_dest = CODCLI, @tpnota = TPNOTA, @numnota = NUMNOTA, @serie = SERIE,
       @dtnota = DTNOTA, @hrhora = HRHORA, @numpedven = NUMPEDVEN
  FROM dbo.MOV_SAIDA
 WHERE CHAVENFE = @chavenfe AND TPNOTA = 144

IF @codfil IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: transferencia com a chave %s nao encontrada na MOV_SAIDA.', 16, 1, @chavenfe);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM dbo.MOV_PEDIDO WHERE CODFIL = @codfil AND TIPOPED = 2 AND NUMPEDVEN = @numpedven)
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: pedido de transferencia da chave %s nao encontrado na MOV_PEDIDO.', 16, 1, @chavenfe);
    RETURN;
END

-- O mesmo número de item no pedido e na nota (como no Gemco)
SET @item = (SELECT COUNT(*) + 1 FROM dbo.MOV_ITSAIDA
              WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND NUMNOTA = @numnota AND SERIE = @serie AND DTNOTA = @dtnota)

/* ---------- Cadastro do produto ---------- */
SELECT @codprod   = pro.CODPROD,
       @codicms   = pro.CODICMS,
       @codicmred = ISNULL(pro.CODICMRED, 0),
       @codicmsub = ISNULL(pro.CODICMSUB, 0),
       @ncm       = pro.NCM,
       @origem    = pro.ORIGEM,
       @codcbs    = pro.CODCBS,
       @codibs    = pro.CODIBS,
       @pesounit  = ISNULL(pro.PESOUNIT, 0),
       @fllote    = ISNULL(pro.FLLOTEVENCTO, 'N')
  FROM dbo.CAD_ITPROD itp
  JOIN dbo.CAD_PROD pro ON pro.CODPROD = itp.CODPROD
 WHERE itp.CODITPROD = @coditprod

IF @codprod IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s nao encontrado na CAD_ITPROD.', 16, 1, @prod_txt);
    RETURN;
END

SELECT @unembal = emb.UNIDMENOR FROM dbo.CAD_EMBAL emb WHERE emb.CODPROD = @codprod AND emb.CODEMBAL = 0

SELECT TOP (1) @codbarra = bar.CODBARRA
  FROM dbo.CAD_CODBARRA bar
 WHERE bar.CODPROD = @codprod AND bar.CODEMBAL = 0
 ORDER BY bar.TSULTALT DESC

SELECT @codsitprod = pco.CODSITPROD
  FROM dbo.CAD_PRECO pco
 WHERE pco.CODFIL = @codfil AND pco.CODITPROD = @coditprod AND pco.CODEMBAL = 0

-- Custo: VEN_PRODFIL da filial 8 (filial de custo da ACAL)
SET @codfilcust = 8

SELECT @cmup = cus.CMUP, @cmupi = cus.CMUPI, @cue = cus.CUE
  FROM dbo.VEN_PRODFIL cus
 WHERE cus.CODFIL = @codfilcust AND cus.CODPROD = @codprod

-- PREÇO DA TRANSFERÊNCIA = custo médio (CMUP) da VEN_PRODFIL da filial 8, em 2 casas, como o Gemco
-- grava (PRECOUNIT = CMUP arredondado). O preço e o total que vieram da FIKON (@precounit/@vltotal)
-- não são usados: total do item = quantidade x preço de custo.
IF ISNULL(@cmup, 0) <= 0
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s sem custo (CMUP) na VEN_PRODFIL da filial 8.', 16, 1, @prod_txt);
    RETURN;
END

SET @precounit = ROUND(@cmup, 2)
SET @vltotal   = ROUND(@qtcomp * @precounit, 2)
SET @U         = CAST(@vltotal AS numeric(28,15)) / @qtcomp

SELECT @cest = CEST FROM dbo.CAD_NCM WHERE NCM = @ncm

/* ---------- Depósito da origem e do destino (CAD_DEPOS; 'L' quando houver) ---------- */
SELECT TOP (1) @tpdepos = dep.TPDEPOS, @local = dep.LOCAL
  FROM dbo.CAD_DEPOS dep
 WHERE dep.CODFIL = @codfil
   AND EXISTS (SELECT 1 FROM dbo.CAD_PRODLOC pl WHERE pl.CODFIL = dep.CODFIL AND pl.TPDEPOS = dep.TPDEPOS AND pl.CODITPROD = @coditprod)
 ORDER BY CASE dep.TPDEPOS WHEN 'L' THEN 0 ELSE 1 END

IF @tpdepos IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s sem estoque cadastrado (CAD_PRODLOC) na filial de origem.', 16, 1, @prod_txt);
    RETURN;
END

SELECT @fisico = ISNULL(FISICO, 0), @resfis = ISNULL(RESFIS, 0), @status_loc = STATUS
  FROM dbo.CAD_PRODLOC
 WHERE CODFIL = @codfil AND TPDEPOS = @tpdepos AND CODITPROD = @coditprod

SELECT TOP (1) @tpdepos_dest = dep.TPDEPOS
  FROM dbo.CAD_DEPOS dep
 WHERE dep.CODFIL = @codfil_dest
   AND EXISTS (SELECT 1 FROM dbo.CAD_PRODLOC pl WHERE pl.CODFIL = dep.CODFIL AND pl.TPDEPOS = dep.TPDEPOS AND pl.CODITPROD = @coditprod)
 ORDER BY CASE dep.TPDEPOS WHEN 'L' THEN 0 ELSE 1 END

IF @tpdepos_dest IS NOT NULL
    SELECT @transito_dest = ISNULL(TRANSITO, 0), @status_dest = STATUS
      FROM dbo.CAD_PRODLOC
     WHERE CODFIL = @codfil_dest AND TPDEPOS = @tpdepos_dest AND CODITPROD = @coditprod

/* ---------- Lotes (só produto com controle de lote; nos demais @lotes é ignorado) ---------- */
IF @fllote = 'S'
BEGIN
    SET @resto = LTRIM(RTRIM(ISNULL(@lotes, '')))

    IF LEN(@resto) = 0
    BEGIN
        RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s controla lote e a FIKON nao informou o lote.', 16, 1, @prod_txt);
        RETURN;
    END

    WHILE LEN(@resto) > 0
    BEGIN
        SET @pos = CHARINDEX('|', @resto)

        IF @pos = 0
        BEGIN
            SET @par = @resto
            SET @resto = ''
        END
        ELSE
        BEGIN
            SET @par = LEFT(@resto, @pos - 1)
            SET @resto = LTRIM(SUBSTRING(@resto, @pos + 1, 4000))
        END

        SET @pos = CHARINDEX(':', @par)
        SET @lote = CASE WHEN @pos > 1 THEN LTRIM(RTRIM(LEFT(@par, @pos - 1))) ELSE '' END
        SET @qtlote_txt = CASE WHEN @pos > 0 THEN LTRIM(RTRIM(SUBSTRING(@par, @pos + 1, 50))) ELSE '' END

        IF LEN(@lote) = 0 OR LEN(@qtlote_txt) = 0 OR @qtlote_txt LIKE '%[^0-9.]%' OR @qtlote_txt LIKE '%.%.%'
        BEGIN
            RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: lote invalido para o produto %s (%s).', 16, 1, @prod_txt, @par);
            RETURN;
        END

        SET @qtlote = CAST(@qtlote_txt AS numeric(9,3))

        IF @qtlote <= 0
        BEGIN
            RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: quantidade zerada no lote %s do produto %s.', 16, 1, @lote, @prod_txt);
            RETURN;
        END

        INSERT INTO @tl (LOTEVENCTO, QTDE) VALUES (@lote, @qtlote)
    END

    SELECT @somalotes = SUM(QTDE) FROM @tl

    IF ISNULL(@somalotes, 0) <> @qtcomp
    BEGIN
        SET @msg = 'SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: soma dos lotes (' + CONVERT(varchar(20), @somalotes)
                 + ') diferente da quantidade (' + CONVERT(varchar(20), @qtcomp) + ') do produto ' + @prod_txt + '.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    -- Saldo de cada lote na origem (QTDE - RESFIS), somando lotes repetidos
    SELECT TOP (1) @lote = t.LOTEVENCTO, @qtlote = t.QTDE,
                   @qtde_lote = ISNULL(lv.QTDE, 0), @resfis_lote = ISNULL(lv.RESFIS, 0)
      FROM (SELECT LOTEVENCTO, SUM(QTDE) QTDE FROM @tl GROUP BY LOTEVENCTO) t
      LEFT JOIN dbo.MOV_LOTEVENCTO lv ON lv.CODFIL = @codfil AND lv.CODITPROD = @coditprod AND lv.LOTEVENCTO = t.LOTEVENCTO
     WHERE lv.LOTEVENCTO IS NULL OR ISNULL(lv.QTDE, 0) - ISNULL(lv.RESFIS, 0) < t.QTDE

    IF @@ROWCOUNT > 0
    BEGIN
        SET @msg = 'SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: lote ' + @lote + ' do produto ' + @prod_txt
                 + ' sem saldo na filial de origem (pedido ' + CONVERT(varchar(20), @qtlote)
                 + ', disponivel ' + CONVERT(varchar(20), @qtde_lote - @resfis_lote) + ').';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END
END

/* ---------- ICMS ---------- */
SELECT @uf = ESTADO FROM dbo.CAD_FILIAL WHERE CODFIL = @codfil
SELECT @codgrptpnota = CODGRPTPNOTA FROM dbo.CAD_TPNOTA WHERE TPNOTA = @tpnota

IF @uf IS NULL OR @codgrptpnota IS NULL
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: filial ou tipo de nota sem UF / grupo de tipo de nota.', 16, 1);
    RETURN;
END

SELECT @ctf_i = CTF, @aliqicm = ISNULL(ALIQUOTA, 0), @obs_i = OBSERVACAO
  FROM dbo.CAD_IMPTRIBUT
 WHERE TPIMP = 'I' AND CODIMP = @codicms AND ESTORIG = @uf AND ESTDEST = @uf AND CODGRPTPNOTA = @codgrptpnota
SET @achou = @@ROWCOUNT

IF @achou = 0
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s sem tributacao de ICMS (CAD_IMPTRIBUT tipo I) para %s.', 16, 1, @prod_txt, @uf);
    RETURN;
END

IF @codicmred > 0
BEGIN
    SELECT @ctf_r = CTF, @aliqicmred = ISNULL(ALIQUOTA, 0), @obs_r = OBSERVACAO
      FROM dbo.CAD_IMPTRIBUT
     WHERE TPIMP = 'R' AND CODIMP = @codicmred AND ESTORIG = @uf AND ESTDEST = @uf AND CODGRPTPNOTA = @codgrptpnota
    SET @achou = @@ROWCOUNT

    IF @achou = 0
    BEGIN
        RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s sem a reducao de ICMS (CAD_IMPTRIBUT tipo R) para %s.', 16, 1, @prod_txt, @uf);
        RETURN;
    END
END

IF @codicmsub > 0
BEGIN
    SELECT @ctf_s = CTF, @aliqicmsub = ISNULL(ALIQUOTA, 0), @obs_s = OBSERVACAO
      FROM dbo.CAD_IMPTRIBUT
     WHERE TPIMP = 'S' AND CODIMP = @codicmsub AND ESTORIG = @uf AND ESTDEST = @uf AND CODGRPTPNOTA = @codgrptpnota
    SET @achou = @@ROWCOUNT

    IF @achou = 0
    BEGIN
        RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s sem a substituicao tributaria (CAD_IMPTRIBUT tipo S) para %s.', 16, 1, @prod_txt, @uf);
        RETURN;
    END
END

-- CTF: ST, depois redução, depois ICMS (mesma ordem do cupom e da view PDV_PRODTRIBUT)
SET @ctf = CASE WHEN @codicmsub > 0 THEN @ctf_s WHEN @codicmred > 0 THEN @ctf_r ELSE @ctf_i END
SET @ctf_txt = ISNULL(CONVERT(varchar(10), @ctf), 'nulo')

IF @ctf IS NULL OR @ctf NOT IN (0, 20, 40, 60)
BEGIN
    RAISERROR('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA: produto %s com CTF nao tratado na transferencia (%s). Nada foi gravado.', 16, 1, @prod_txt, @ctf_txt);
    RETURN;
END

IF @ctf = 0
BEGIN
    SET @vlbaseicm   = @vltotal
    SET @vlicm       = ROUND(@vltotal * @aliqicm / 100, 2, 1)
    SET @vlbaseicmsf = ROUND(@U, 9)
    SET @vlicmf      = ROUND(@U * @aliqicm / 100, 9)
END
ELSE IF @ctf = 20
BEGIN
    SET @vlbaseicm   = ROUND(@vltotal * (100 - @aliqicmred) / 100, 2)
    SET @vlntribut   = @vltotal - @vlbaseicm
    SET @vlicm       = ROUND(@vlbaseicm * @aliqicm / 100, 2, 1)
    SET @vlbaseicmsf = ROUND(@U * (100 - @aliqicmred) / 100, 9)
    SET @vlicmf      = ROUND(@U * (100 - @aliqicmred) / 100 * @aliqicm / 100, 9)
    SET @vlntributf  = ROUND(@U * @aliqicmred / 100, 9)
END
ELSE IF @ctf = 40
BEGIN
    SET @vlisento    = @vltotal
    SET @vlisentof   = ROUND(@U, 9)
END
ELSE IF @ctf = 60
BEGIN
    SET @vloutras     = @vltotal
    SET @vloutrasf    = ROUND(@U, 9)
    SET @vlicmoperstf = ROUND(@U * @aliqicm / 100, 9)
    SET @aliqicmsubuf = @aliqicm
END

IF @ctf = 60
BEGIN
    SET @codnatop = 540        -- CFOP 5.409 (transferência com ST)
    SET @codnatopcompl = 9
END
ELSE
BEGIN
    SET @codnatop = 515        -- CFOP 5.152 (transferência)
    SET @codnatopcompl = 2
END

SET @obsfiscal = CASE WHEN @codicmsub > 0 THEN @obs_s WHEN @codicmred > 0 THEN @obs_r ELSE @obs_i END

/* ---------- CBS / IBS ---------- */
SELECT TOP (1) @aliqcbs = ISNULL(ALIQUOTA, 0), @cstcbs = CST, @clastribcbs = CLASTRIB
  FROM dbo.CAD_IMPTRIBUT_REFORMA
 WHERE TPIMP = 'CBS' AND CODIMP = @codcbs AND CODGRPTPNOTA = @codgrptpnota AND ESTORIG = 'BR' AND ESTDEST = 'BR'
   AND @dtnota BETWEEN DTVIGENCIAINI AND DTVIGENCIAFIM
 ORDER BY DTVIGENCIAINI DESC

SELECT TOP (1) @aliqibs = ISNULL(ALIQUOTA, 0), @aliqibsmun = ISNULL(ALIQMUNICIPIO, 0), @cstibs = CST, @clastribibs = CLASTRIB
  FROM dbo.CAD_IMPTRIBUT_REFORMA
 WHERE TPIMP = 'IBS' AND CODIMP = @codibs AND CODGRPTPNOTA = @codgrptpnota AND ESTORIG = @uf AND ESTDEST = @uf
   AND @dtnota BETWEEN DTVIGENCIAINI AND DTVIGENCIAFIM
 ORDER BY DTVIGENCIAINI DESC

IF @aliqcbs > 0 OR @aliqibs > 0
BEGIN
    SET @vlbasecbs = ROUND(@U, 9, 1)
    SET @vlbaseibs = ROUND(@U, 9, 1)
    SET @vlcbs     = ROUND(@U * @aliqcbs / 100, 9, 1)
    SET @vlibs     = ROUND(@U * @aliqibs / 100, 9, 1)
    IF @aliqibsmun > 0
    BEGIN
        SET @vlbaseibsmun = ROUND(@U, 9, 1)
        SET @vlibsmun     = ROUND(@U * @aliqibsmun / 100, 9, 1)
    END
END

/* ---------- Item do pedido (já faturado) ---------- */
INSERT INTO dbo.MOV_ITPED (
    CODFIL, TIPOPED, NUMPEDVEN, CODITPROD, ITEM, CODCLI, QTCOMP, PRECOUNIT, PRECOORIG,
    ALIQICM, ALIQICMSUB, ALIQICMSUBUF, CTF, LOCAL, TPDEPOS, FILORIG, CUBAGEM, UNEMBAL, PESO, PESOLIQ,
    STATUS, TPNOTA, NUMNOTA, DTNOTA, DTPEDIDO, DTENTREGA, CMUP, CUE, CODSITPROD, QTEMB, VLTOTITEM,
    QTORIG, QTLIB, QTEMITIDO, QTFAT, FLLOTEVENCTO, FLLIBFAT, TPPED, CODBARRA, FLATUTRAN, CONVERSAO,
    DTDAV, HRDAV, FLENTPARC, FLSEPARARETDEP, FLPEDVENENDER,
    -- CODEMBAL obrigatório na prática: as telas do Gemco ligam MOV_ITPED.CODEMBAL = CAD_EMBAL.CODEMBAL
    -- (com NULL o item some da tela). Os demais: 0 / 'N' como o Gemco grava.
    CODEMBAL, ALIQICMRED, BLOCO, DPI, QTRESERV, ORIGEM, QTEMBPAD, FLVDANTEC, VLDESCITEM, VLDESCITEMRAT,
    QTVOLUME, CMUPI, VLBASEICMS, VLBASEICMSSUB, VLICM, VLICMRET, VLOUTRAS, VLIPI, PORCIPI, FLPREINDIG,
    FLALTDAV, QTRESLIB, QTENCOMENDA, VLFRETE, VLDESPACES, VLOUTDESP, VLSEGURO, VLDESPFIN
) VALUES (
    @codfil, 2, @numpedven, @coditprod, @item, @codfil_dest, @qtcomp, @precounit, @precounit,
    @aliqicm, @aliqicmsub, @aliqicmsubuf, @ctf, @local, @tpdepos, @codfil, 0, @unembal, @qtcomp * @pesounit, @qtcomp * @pesounit,
    6, @tpnota, @numnota, @dtnota, @dtnota, @dtnota, @cmup, @cue, @codsitprod, 1, @vltotal,
    @qtcomp, 0, @qtcomp, @qtcomp, @fllote, 'S', 'E', @codbarra, 'S', 1,
    '18991230', '19000101', 'N', 'N', 'N',
    0, @aliqicmred, 0, 0, 0, 0, 0, 'N', 0, 0,
    0, ISNULL(@cmupi, 0), 0, 0, 0, 0, 0, 0, 0, 'N',
    'N', 0, 0, 0, 0, 0, 0, 0
);

/* ---------- Item da nota ---------- */
INSERT INTO dbo.MOV_ITSAIDA (
    CODFIL, TPNOTA, NUMNOTA, DTNOTA, SERIE, CODITPROD, ITEM, QTCOMP, PRECOUNIT, PRECOUNITLIQ, PRECOORIG,
    ALIQICM, ALIQICMSUB, ALIQICMRED, ALIQICMUF, ALIQICMSUBUF, LOCAL, TPDEPOS, CUBAGEM, DPI, STATUS,
    NUMPEDVEN, UNEMBAL, CODCLI, VLFRETE, HRHORA, CODSITPROD, FILPED, FILORIG,
    VLBASEICMS, VLISENTO, VLNTRIBUT, VLOUTRAS, VLICM, VLBASEICMSSUB, VLICMRET,
    VLDESCITEM, VLDESCITEMRAT, QTEMB, CODBARRA, CMUP, CMUPI, CUE, CUEORIG,
    CODNATOP, CODNATOPCOMPL, CTF, VLTOTITEM, VLTOTAL, FLLOTEVENCTO, VLBASEICMD, VLICMD,
    DTATUEST, CONVERSAO, FLMDVCOMPSUSP, FLMDVLOCAL, FLMDVPROMOCAO, FLRUPTURAMINQT, FLRUPTURAVDZERO,
    FLPREINDIG, FLATUTRAN, CODVENDR, OBSFISCAL, ORIGEMPROD, CEST,
    VLBASEICMSF, VLICMF, VLISENTOF, VLNTRIBUTF, VLOUTRASF, VLICMOPERSTF,
    VLBASEICMSEFETIVO, VLICMSEFETIVO, VLBASESTRETANT, VLICMSTRETANT, VLBASEFCPSTRETANT, VLSUBSTITUTOSTRETANT,
    CLASTRIBCBS, CLASTRIBIBS, CSTCBS, CSTIBS, ALIQCBS, ALIQIBS, ALIQIBSMUN, ALIQIS,
    VLBASECBS, VLBASEIBS, VLBASEIBSMUN, VLBASEIS, VLCBS, VLIBS, VLIBSMUN, VLIS,
    CODEMBAL                -- 0 como o Gemco (NULL quebra a ligação com a CAD_EMBAL nas telas)
) VALUES (
    @codfil, @tpnota, @numnota, @dtnota, @serie, @coditprod, @item, @qtcomp, @precounit, 0, @precounit,
    @aliqicm, @aliqicmsub, @aliqicmred, @aliqicm, @aliqicmsubuf, @local, @tpdepos, 0, 0, 2,
    @numpedven, @unembal, @codfil_dest, 0, @hrhora, @codsitprod, @codfil, @codfil,
    @vlbaseicm, @vlisento, @vlntribut, @vloutras, @vlicm, 0, 0,
    0, 0, 1, @codbarra, @cmup, @cmupi, @cue, @cmup,
    @codnatop, @codnatopcompl, @ctf, @vltotal, @vltotal, @fllote, 0, 0,
    GETDATE(), 1, 'N', 'N', 'N', 'N', 'N',
    'N', 'P', 0, @obsfiscal, @origem, @cest,
    @vlbaseicmsf, @vlicmf, @vlisentof, @vlntributf, @vloutrasf, @vlicmoperstf,
    0, 0, 0, 0, 0, 0,
    @clastribcbs, @clastribibs, @cstcbs, @cstibs, @aliqcbs, @aliqibs, @aliqibsmun, 0,
    @vlbasecbs, @vlbaseibs, @vlbaseibsmun, 0, @vlcbs, @vlibs, @vlibsmun, 0,
    0
);

-- A NF-e foi emitida pela FIKON: tira o item da fila de emissão do Gemco que o trigger
-- REPLICA_NFE_SAIDA acabou de alimentar (mesma transação; a linha nunca chega a ser confirmada).
DELETE FROM dbo.INT_NFE_SAIDA
 WHERE CODFIL = @codfil AND TPNOTA = @tpnota AND SERIE = @serie AND NUMNOTA = @numnota
   AND DTNOTA = @dtnota AND CODITPROD = @coditprod AND ITEM = @item AND STATUS = 0;

/* ---------- Estoque, etapa do pedido: trânsito no destino e reserva na origem ---------- */
IF @tpdepos_dest IS NOT NULL
BEGIN
    EXEC dbo.SPU_PROLOCI
         @VERSAO = 1, @CODFIL = @codfil_dest, @TPDEPOS = @tpdepos_dest, @CODITPROD = @coditprod,
         @FISICO = 0, @RESFIS = 0, @LOGICO = 0, @TRANSITO = @qtcomp, @TECNICO = 0, @MOSTRUARIO = 0,
         @FUTURO = 0, @CONSIGNACAO = 0, @STATUS = @status_dest, @CODPROD = NULL, @QTVDCONSIG = 0,
         @DTULTENT = NULL, @QTDULTENT = NULL, @TPNOTAULTENT = NULL, @NFULTENT = NULL, @ENCOMENDA = 0,
         @ESTDETERCEIROSNOSSOPODER = 0, @ESTEMPODERTERCEIROS = 0, @CUEPIN = 0, @RESFISTERCEIRONOSSOPODER = 0

    INSERT INTO dbo.MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,
           FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO,
           QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS, RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS,
           TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC)
    VALUES (@codfil_dest, @numpedven, 0, GETDATE(), @tpnota, 'S', 1, @coditprod,
           0, 0, 0, 0, 0, 0, @transito_dest, 0, 0,
           @qtcomp, 'TRANSITO;', 'N', 0, 0, 0, 0, 0,
           0, @transito_dest + @qtcomp, 0, 0, @codfil, @dtnota, 'GRAVAITENSPED',
           '{CALL SPU_PROLOCI(1, ' + CONVERT(varchar, @codfil_dest) + ', ' + @tpdepos_dest + ', ' + CONVERT(varchar, @coditprod)
             + ', 0, 0, 0, ' + CONVERT(varchar, @qtcomp) + ', ...)}',
           @identproc)
END

EXEC dbo.SPU_PROLOCI
     @VERSAO = 1, @CODFIL = @codfil, @TPDEPOS = @tpdepos, @CODITPROD = @coditprod,
     @FISICO = 0, @RESFIS = @qtcomp, @LOGICO = 0, @TRANSITO = 0, @TECNICO = 0, @MOSTRUARIO = 0,
     @FUTURO = 0, @CONSIGNACAO = 0, @STATUS = @status_loc, @CODPROD = NULL, @QTVDCONSIG = 0,
     @DTULTENT = NULL, @QTDULTENT = NULL, @TPNOTAULTENT = NULL, @NFULTENT = NULL, @ENCOMENDA = 0,
     @ESTDETERCEIROSNOSSOPODER = 0, @ESTEMPODERTERCEIROS = 0, @CUEPIN = 0, @RESFISTERCEIRONOSSOPODER = 0

INSERT INTO dbo.MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,
       FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO,
       QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS, RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS,
       TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC)
VALUES (@codfil, @numpedven, 0, GETDATE(), @tpnota, 'S', 1, @coditprod,
       @fisico, @resfis, 0, 0, 0, 0, 0, 0, 0,
       @qtcomp, 'RESFIS;', 'N', @fisico, @resfis + @qtcomp, 0, 0, 0,
       0, 0, 0, 0, @codfil, @dtnota, 'GRAVAITENSPED',
       '{CALL SPU_PROLOCI(1, ' + CONVERT(varchar, @codfil) + ', ' + @tpdepos + ', ' + CONVERT(varchar, @coditprod)
         + ', 0, ' + CONVERT(varchar, @qtcomp) + ', ...)}',
       @identproc)

/* ---------- Estoque, etapa da nota: baixa físico e reserva na origem ---------- */
SET @qtbaixa = -@qtcomp

EXEC dbo.SPU_PROLOCI
     @VERSAO = 1, @CODFIL = @codfil, @TPDEPOS = @tpdepos, @CODITPROD = @coditprod,
     @FISICO = @qtbaixa, @RESFIS = @qtbaixa, @LOGICO = 0, @TRANSITO = 0, @TECNICO = 0, @MOSTRUARIO = 0,
     @FUTURO = 0, @CONSIGNACAO = 0, @STATUS = @status_loc, @CODPROD = NULL, @QTVDCONSIG = 0,
     @DTULTENT = NULL, @QTDULTENT = NULL, @TPNOTAULTENT = NULL, @NFULTENT = NULL, @ENCOMENDA = 0,
     @ESTDETERCEIROSNOSSOPODER = 0, @ESTEMPODERTERCEIROS = 0, @CUEPIN = 0, @RESFISTERCEIRONOSSOPODER = 0

INSERT INTO dbo.MOV_EXTRATOPROD (CODFIL, NUMPED, NUMNOTA, DATAHORAID, TPNOTA, TIPOMOV, MODULO, CODITPROD,
       FISICO, RESFIS, ENCOMENDA, FUTURO, LOGICO, TECNICO, TRANSITO, CONSIGNACAO, MOSTRUARIO,
       QTDEATUALIZADO, CAMPOSATUALIZADO, FLERRO, FISICOPOS, RESFISPOS, ENCOMENDAPOS, FUTUROPOS, LOGICOPOS,
       TECNICOPOS, TRANSITOPOS, CONSIGNACAOPOS, MOSTRUARIOPOS, CODFILLOG, DTPROC, ROTINA, COMANDOSQL, IDENTPROC)
VALUES (@codfil, @numpedven, @numnota, GETDATE(), @tpnota, 'S', 3, @coditprod,
       @fisico, @resfis + @qtcomp, 0, 0, 0, 0, 0, 0, 0,
       @qtbaixa, 'FISICO;RESFIS;', 'N', @fisico - @qtcomp, @resfis, 0, 0, 0,
       0, 0, 0, 0, @codfil, @dtnota, 'GRAVAITENSNOTAFISCAL',
       '{CALL SPU_PROLOCI(1, ' + CONVERT(varchar, @codfil) + ', ' + @tpdepos + ', ' + CONVERT(varchar, @coditprod)
         + ', ' + CONVERT(varchar, @qtbaixa) + ', ' + CONVERT(varchar, @qtbaixa) + ', ...)}',
       @identproc)

/* ---------- Lotes: registro do lote na nota e baixa do saldo do lote na origem ---------- */
IF @fllote = 'S'
BEGIN
    -- Estado final das linhas nativas depois da nota: QTDE = quantidade, RESFIS 0, STATUS 6, QTLIB 0.
    -- QTESTOQUE = saldo do lote antes da transferência (como no pedido do Gemco).
    INSERT INTO dbo.MOV_LOTEVENCTO_NF (
        CODFIL, TPNOTA, NUMNOTA, NUMPEDVEN, SERIE, CODITPROD, CODFORNE, LOTEVENCTO, DTVENCTO, DTNOTA,
        DTPEDIDO, QTDE, RESFIS, STATUS, BLOQUEADO, CODUSER, TIPOPED, QTEMB, CONVERSAO, CODEMBAL,
        FILPED, FLVDANTEC, ITPEDITEM, QTLIB, QTORIG, QTRESLIB, QTESTOQUE, DTATUEST
    )
    SELECT @codfil, @tpnota, @numnota, @numpedven, @serie, @coditprod, 0, t.LOTEVENCTO, NULL, @dtnota,
           @dtnota, t.QTDE, 0, 6, 0, @coduser, 2, 1, 1, 0,
           @codfil, 'N', @item, 0, t.QTDE, 0, ISNULL(lv.QTDE, 0), GETDATE()
      FROM (SELECT LOTEVENCTO, SUM(QTDE) QTDE FROM @tl GROUP BY LOTEVENCTO) t
      JOIN dbo.MOV_LOTEVENCTO lv ON lv.CODFIL = @codfil AND lv.CODITPROD = @coditprod AND lv.LOTEVENCTO = t.LOTEVENCTO;

    -- Pedido: RESFIS + q; nota: QTDE - q e RESFIS - q. Resultado: QTDE - q.
    UPDATE lv WITH (READCOMMITTED)
       SET QTDE = ISNULL(lv.QTDE, 0) - t.QTDE
      FROM dbo.MOV_LOTEVENCTO lv
      JOIN (SELECT LOTEVENCTO, SUM(QTDE) QTDE FROM @tl GROUP BY LOTEVENCTO) t ON t.LOTEVENCTO = lv.LOTEVENCTO
     WHERE lv.CODFIL = @codfil AND lv.CODITPROD = @coditprod;

    -- Lote zerado sai da MOV_LOTEVENCTO (mesma regra do faturamento do Gemco).
    DELETE lv
      FROM dbo.MOV_LOTEVENCTO lv
      JOIN (SELECT DISTINCT LOTEVENCTO FROM @tl) t ON t.LOTEVENCTO = lv.LOTEVENCTO
     WHERE lv.CODFIL = @codfil AND lv.CODITPROD = @coditprod
       AND ISNULL(lv.QTDE, 0) + ISNULL(lv.BLOQUEADO, 0) = 0;
END

/* ---------- Totais: nota (fiscais, peso e natureza) e pedido ---------- */
UPDATE s
   SET VLMERCAD   = t.vltotal,
       VLTOTAL    = t.vltotal,
       VLBASEICMS = t.vlbaseicms,
       VLICM      = t.vlicm,
       VLOUTRAS   = t.vloutras,
       VLISENTO   = t.vlisento,
       PESO       = ISNULL(s.PESO, 0) + (@qtcomp * @pesounit),
       PESOLIQ    = ISNULL(s.PESOLIQ, 0) + (@qtcomp * @pesounit),
       CODNATOP         = CASE WHEN t.qt_sem_st > 0 THEN 515 ELSE NULL END,
       CODNATOPCOMPL    = CASE WHEN t.qt_sem_st > 0 THEN 2 ELSE NULL END,
       CODNATOPDIF      = CASE WHEN t.qt_st > 0 THEN 540 ELSE 0 END,
       CODNATOPDIFCOMPL = CASE WHEN t.qt_st > 0 THEN 9 ELSE 0 END
  FROM dbo.MOV_SAIDA s
 CROSS APPLY (SELECT SUM(i.VLTOTAL) vltotal, SUM(i.VLBASEICMS) vlbaseicms, SUM(i.VLICM) vlicm,
                     SUM(i.VLOUTRAS) vloutras, SUM(i.VLISENTO) vlisento,
                     SUM(CASE WHEN i.CTF = 60 THEN 1 ELSE 0 END) qt_st,
                     SUM(CASE WHEN i.CTF = 60 THEN 0 ELSE 1 END) qt_sem_st
                FROM dbo.MOV_ITSAIDA i
               WHERE i.CODFIL = s.CODFIL AND i.TPNOTA = s.TPNOTA AND i.NUMNOTA = s.NUMNOTA
                 AND i.SERIE = s.SERIE AND i.DTNOTA = s.DTNOTA) t
 WHERE s.CODFIL = @codfil AND s.TPNOTA = @tpnota AND s.NUMNOTA = @numnota AND s.SERIE = @serie AND s.DTNOTA = @dtnota;

UPDATE p
   SET VLMERCAD      = t.vltotal,
       VLTOTAL       = t.vltotal,
       VLVDVISTA     = t.vltotal,
       VLTOTITEMACUM = t.vltotal
  FROM dbo.MOV_PEDIDO p
 CROSS APPLY (SELECT SUM(i.VLTOTITEM) vltotal FROM dbo.MOV_ITPED i
               WHERE i.CODFIL = p.CODFIL AND i.TIPOPED = p.TIPOPED AND i.NUMPEDVEN = p.NUMPEDVEN) t
 WHERE p.CODFIL = @codfil AND p.TIPOPED = 2 AND p.NUMPEDVEN = @numpedven;
GO

-- Conferência: as duas procedures devem aparecer com a data de hoje.
SELECT name, create_date, modify_date FROM sys.objects
 WHERE name IN ('SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_SAIDA', 'SP_FIKON_INTEGRA_TRANSFERENCIA_MOV_ITSAIDA')
 ORDER BY name;
GO
