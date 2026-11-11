/*
  09 - Impostos do cupom FIKON: reescrita da dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA  -  10/11/2026

  Problema (cupons 84 a 92, filial 15, série 444, dev DB-TREINO):
    Os itens do cupom FIKON iam para a MOV_ITSAIDA com os impostos errados ou vazios, e o cabeçalho
    (MOV_SAIDA) ficava sem os totais fiscais:
      - CTF fixo 90 para todo produto (a tributação do cadastro era ignorada);
      - ALIQICMSUB sempre 0 (o LEFT JOIN do ICMS ST comparava as colunas da linha errada);
      - ALIQICMSUBUF fixo 20, ALIQICMUF = ALIQICM, ORIGEMPROD 0, PERCREDUTOR 0;
      - VLOUTRAS / VLOUTRASF / VLBASEICMSEFETIVO / VLICMSEFETIVO nulos;
        VLICMOPERSTF recebia o VLICMSEFETIVO;
      - VLBASEICMSSUB / VLICMRET / DPI nulos;
      - CEST nulo; IBPT (Lei 12.741) nulo; base de CBS/IBS zerada, alíquotas 0,9/0,1 fixas;
      - OBSFISCAL com texto fixo de ST até em produto sem ST;
      - natureza de operação 540/5 para tudo (a regra por estado nunca entrava);
      - cabeçalho com VLMERCAD 0, ICMS/IBPT/CBS sem total e CODNATOP nulo.

  Como as regras foram levantadas:
    Notas NFC-e nativas do PDV do Gemco (filial 15, maio/2026, modelo 65, TPNOTA 251).
    Cada regra abaixo foi simulada nos 6.606 itens de 2.760 notas e comparada campo a campo com o
    gravado. Bateu em mais de 99%. As diferenças restantes são defeitos do próprio PDV:
      - desconto no total rateado depois do cálculo;
      - itens repetidos com valores trocados entre si;
      - caixas com a tabela do IBPT desatualizada;
      - cadastro alterado depois da venda.
    O cupom FIKON não tem nenhum desses casos.

  Regras (T = total líquido do item, Q = quantidade, U = T/Q, A = ALIQICM, R = ALIQICMRED,
  trunc = truncar em 2 casas):
    CTF, como a view PDV_PRODTRIBUT do Gemco:
      - CODICMSUB > 0 -> CTF da linha 'S' da CAD_IMPTRIBUT;
      - senão CODICMRED > 0 -> CTF da linha 'R';
      - senão CTF da linha 'I'.
      Todas com ESTORIG = ESTDEST = UF da filial e o CODGRPTPNOTA do tipo de nota.
      ALIQICM, ALIQICMRED e ALIQICMSUB vêm das linhas I, R e S.
    Campos de ICMS por CTF:

      | CTF | Totais do item                                   | Campos unitários (9 casas)                        |
      |-----|--------------------------------------------------|---------------------------------------------------|
      | 0   | VLBASEICMS = T; VLICM = trunc(T*A/100)           | VLBASEICMSF = U; VLICMF = U*A/100                 |
      | 20  | VLBASEICMS = trunc(T*(100-R)/100);               | VLBASEICMSF, VLICMF, VLNTRIBUTF                   |
      |     | VLICM = trunc(VLBASEICMS sem truncar * A/100);   | na mesma proporção, sobre U                       |
      |     | VLNTRIBUT = trunc(T*R/100)                       |                                                   |
      | 40  | VLISENTO = T                                     | VLISENTOF = U                                     |
      | 60  | VLOUTRAS = T; VLBASEICMSEFETIVO = T;             | VLOUTRASF = U; VLICMOPERSTF = U*A/100 (6 casas)   |
      |     | VLICMSEFETIVO = trunc(T*A/100)                   |                                                   |
      | 90  | campos de ICMS 0                                 | VLBASEICMD = U; VLICMD = U*A/100                  |

      Outro CTF, ou falta de linha de tributação no cadastro: a procedure dá erro e não grava o item.
    Natureza de operação:
      - CAD_TRIBUT.FLNATOPSUB = 'S' -> CODNATOP 540 / CODNATOPCOMPL 5 (CFOP 5.405);
      - senão 510 / 2 (CFOP 5.102).
    CEST: CAD_NCM do NCM do produto.
    OBSFISCAL: nula no modelo 65; no modelo 55, a OBSERVACAO da linha de tributação usada.
    IBPT (só modelo 65), da FIS_TABIBPT:
      - busca: NCM + EX da TIPI do produto, UF da filial, TABELA 0, a tabela vigente na data da nota.
      - alíquota federal: ALIQNAC; ALIQIMP para produto de origem estrangeira (ORIGEM 1, 2, 3 ou 8).
      - alíquotas estadual e municipal: ALIQEST e ALIQMUN.
      - valores: trunc(T*alíquota/100).
      - sem linha para o NCM + EX: tudo 0 e chave/fonte/versão vazias, como faz o PDV.
    CBS/IBS, da CAD_IMPTRIBUT_REFORMA (vigência pela data da nota, CODIMP = CODCBS/CODIBS do produto):
      - base = U truncado em 9 casas; valor = U*alíquota/100 truncado em 9 casas;
      - CST e cClassTrib da própria tabela;
      - sem configuração no cadastro: tudo 0, e o trigger não calcula.
      No modelo 65 o trigger da MOV_ITSAIDA mantém esses valores. No 55 ele recalcula pela regra do ERP.
    PIS/COFINS: continuam vindo do trigger da MOV_ITSAIDA, que tira o ICMS da base (VLICMF / VLICMD).
      Com os campos de ICMS certos, o PIS/COFINS sai igual ao do PDV.
    DPI: VLDESCITEM / (QTCOMP*PRECOUNIT) * 100, truncado em 9 casas.
    Campos que o PDV grava fixos: ALIQICMSUBUF 0, ALIQICMUF NULL, ORIGEMPROD NULL, PERCREDUTOR NULL,
      VLBASEICMSSUB 0, VLICMRET 0.

  Cabeçalho (MOV_SAIDA), recalculado com todos os itens da nota a cada item gravado:
    - VLMERCAD = soma do VLTOTAL dos itens + VLDESCONTO do cabeçalho;
    - VLTOTAL = soma do VLTOTAL;
    - VLBASEICMS, VLICM, VLOUTRAS e VLISENTO = somas;
    - VLBASEICMD e VLICMD = trunc(soma de unitário*QTCOMP).
    Só no modelo 65:
    - IBPT: VLIBPT, VLIBPTEST e VLIBPTMUN = somas;
      ALIQIBPT, ALIQIBPTEST e ALIQIBPTMUN = soma / VLTOTAL * 100, arredondado em 2 casas;
      CHAVEIBPT e FONTEIBPT do item;
    - CBS/IBS: VLBASECBS, VLBASEIBS e VLBASEIBSMUN = soma de base*QTCOMP (2 casas);
      VLCBS, VLIBS e VLIBSMUN = trunc(soma de valor*QTCOMP);
    - natureza de operação: CODNATOP 510 / CODNATOPCOMPL 2 / CODNATOPDIF 540 / CODNATOPDIFCOMPL 5,
      como em 100% das NFC-e nativas.

  Outras correções nesta reescrita:
    - Produto sem cadastro completo (o cursor não traz linha): antes o item era pulado sem aviso e o cupom
      ficava sem ele; agora dá erro.
    - Cursor LOCAL. No CATCH ele é fechado ANTES do THROW; antes ficava aberto e a chamada seguinte, na
      mesma conexão, falhava.
    - QTCOMP zero ou negativa: erro, em vez de divisão por zero.
    - O MODELONF vem do cabeçalho da nota (MOV_SAIDA), e não mais da série.

  Pontos para validar com o fiscal (não mudam o ICMS):
    - IBPT de produto importado (ORIGEM 1/2/3/8): usa ALIQIMP, como manda a Lei 12.741. Não houve venda
      nativa desses produtos para confirmar o que o PDV faz. Na base há 73 produtos assim.
    - O XML da NFC-e é emitido pela FIKON. Se a FIKON calcular diferente do Gemco, o XML e o Gemco
      divergem. Vale conferir alguns cupons contra o XML.

  Como rodar: no SSMS, conectado no servidor certo e no banco dbgemco, executar o script INTEIRO (F5).
    - O 1º bloco guarda a versão atual como SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT09.
      Se a cópia não puder ser feita, o script para (SET NOEXEC ON) e nada é alterado.
    - Depois vem o ALTER PROC completo.
  Para voltar atrás: abrir a _BKP_SCRIPT09, trocar o nome pelo original e executar como ALTER.

  Os cupons já gravados (84 a 92) não são corrigidos por este script: ele só vale para os próximos.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Cópia de segurança ===================== */
DECLARE @def nvarchar(max);

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT09') IS NULL
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA'));
    IF @def IS NOT NULL AND @def LIKE N'%PROC%[[]dbo].[[]SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]%'
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA]', N'[dbo].[SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT09]');
        EXEC sys.sp_executesql @def;
    END
END

IF OBJECT_ID('dbo.SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT09') IS NULL
BEGIN
    RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
    SET NOEXEC ON;   -- o bloco seguinte não é executado
END
ELSE
    PRINT 'Copia guardada: SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT09.';
GO

/* ===================== 2. SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA ===================== */
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

-- Conferência: a procedure e a cópia devem aparecer.
SELECT name, modify_date FROM sys.objects
 WHERE name IN ('SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA', 'SP_FIKON_INTEGRA_CUPOM_MOV_ITSAIDA_BKP_SCRIPT09')
 ORDER BY name;
GO

/* ===================== 3. Conferência depois de integrar um cupom NOVO =====================
   Troque a chave abaixo pela do cupom novo e rode só este bloco.
   O que conferir:
     - CTF do cadastro (ex.: 60 ou 90, não mais 90 fixo);
     - campos de ICMS conforme a regra do CTF;
     - CEST preenchido;
     - IBPT com chave/versão da tabela vigente;
     - base de CBS/IBS > 0;
     - cabeçalho com VLMERCAD, totais de ICMS/IBPT/CBS e CODNATOP 510.

DECLARE @chave varchar(44) = '<chave do cupom novo>';

SELECT i.ITEM, i.CODITPROD, i.CTF, i.ALIQICM, i.ALIQICMRED, i.ALIQICMSUB, i.QTCOMP, i.VLTOTAL,
       i.VLBASEICMS, i.VLICM, i.VLNTRIBUT, i.VLISENTO, i.VLOUTRAS, i.VLBASEICMSF, i.VLICMF, i.VLOUTRASF,
       i.VLBASEICMD, i.VLICMD, i.VLBASEICMSEFETIVO, i.VLICMSEFETIVO, i.VLICMOPERSTF,
       i.CODNATOP, i.CODNATOPCOMPL, i.OBSFISCAL, i.CEST, i.DPI,
       i.ALIQIBPT, i.VLIBPT, i.ALIQIBPTEST, i.VLIBPTEST, i.CHAVEIBPT, i.VERSAOIBPT,
       i.VLBASECBS, i.ALIQCBS, i.VLCBS, i.VLBASEIBS, i.ALIQIBS, i.VLIBS, i.CSTCBS, i.CLASTRIBCBS,
       i.VLBASEPIS, i.PPIS, i.VLPPIS, i.PCONTSOC, i.VLPCONTSOC, i.CSTPIS
  FROM MOV_SAIDA s
  JOIN MOV_ITSAIDA i ON i.CODFIL = s.CODFIL AND i.TPNOTA = s.TPNOTA AND i.NUMNOTA = s.NUMNOTA AND i.SERIE = s.SERIE AND i.DTNOTA = s.DTNOTA
 WHERE s.CHAVENFE = @chave
 ORDER BY i.ITEM;

SELECT s.NUMNOTA, s.SERIE, s.MODELONF, s.VLMERCAD, s.VLTOTAL, s.VLBASEICMS, s.VLICM, s.VLOUTRAS, s.VLISENTO,
       s.VLBASEICMD, s.VLICMD, s.VLIBPT, s.ALIQIBPT, s.VLIBPTEST, s.ALIQIBPTEST, s.CHAVEIBPT,
       s.VLBASECBS, s.VLCBS, s.VLBASEIBS, s.VLIBS, s.CODNATOP, s.CODNATOPCOMPL, s.CODNATOPDIF, s.CODNATOPDIFCOMPL
  FROM MOV_SAIDA s
 WHERE s.CHAVENFE = @chave;
*/
