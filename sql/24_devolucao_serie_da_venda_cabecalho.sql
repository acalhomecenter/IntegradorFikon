/*
  24 - Devolução FIKON: série da venda no cabeçalho da devolução  -  18/11/2026
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.
  A SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO está igual nas duas bases (SHA-256 A89ACC4D...); o script confere de novo.

  Problema (devoluções 1 e 2 série 2 da DM, filial 15, 18/11/2026):
    A proc lia a nota de saída da ENT_NOTASAI pegando a coluna SERIE (série da DEVOLUÇÃO) no lugar de SERIESAI
    (série da VENDA). Efeitos:
      - OBSFISCAL "NF: 5 SERIE: 2 ..." em vez de "NF: 5 SERIE: U06 ...";
      - o update de status da venda não achava a nota: venda devolvida por inteiro ficava STATUS 7 (parcial)
        em vez de 8. Vem desde a primeira versão (antes a série da devolução era sempre '1').
    Também: o total dos itens e a leitura da ENT_NOTASAI não filtravam remetente e série da devolução, e o VALOR
    do OBSFISCAL era o da devolução; nas devoluções do próprio Gemco o VALOR é o total da venda.

  O que muda (procedure completa abaixo):
    1. ENT_NOTASAI lida pela chave completa da devolução (filial, tipo, remetente, série, número, data), com SERIESAI.
    2. Total dos itens (ENT_ITENT) com remetente e série.
    3. OBSFISCAL: "NF: <venda> SERIE: <série da venda> DT: <data da venda> VALOR: <total da venda>".
    4. Status da venda: 8 quando tudo devolvido, 7 parcial (agora acha a venda).
    5. Para com erro claro se a chave da devolução não existir na ENT_NOTA.
  Os registros já gravados são corrigidos no script 25 (só produção).

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
    - O bloco 1 confere a versão da procedure e guarda a cópia SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_SCRIPT24.
  Para voltar atrás: abrir a cópia _BKP_SCRIPT24, trocar o nome pelo original e executar como ALTER.
*/
SET NOCOUNT ON;
GO

/* ===================== 1. Conferência da versão e cópia de segurança ===================== */
DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO'));

IF @def IS NULL
   OR (HASHBYTES('SHA2_256', @def) <> 0xA89ACC4D2C9DADB1D5C559B6D38ADCFCE25FEBA9945E1A6F6B694E5053D89A0F
       AND CHARINDEX(N'script 24', @def) = 0)
BEGIN
    RAISERROR('Nada foi alterado: SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO nao existe ou esta numa versao diferente da esperada.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_SCRIPT24') IS NULL
    BEGIN
        SET @def = REPLACE(@def, N'[dbo].[SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO]', N'[dbo].[SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_SCRIPT24]');
        EXEC sys.sp_executesql @def;
    END

    IF OBJECT_ID('dbo.SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_SCRIPT24') IS NULL
    BEGIN
        RAISERROR('Nao foi possivel guardar a copia de seguranca. Nada foi alterado.', 16, 1);
        SET NOEXEC ON;
    END
    ELSE
        PRINT 'Copia guardada: SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_SCRIPT24.';
END
GO

/* ===================== 2. SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO (completa) ===================== */
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

SET NOEXEC OFF;
GO

SELECT o.name, o.modify_date,
       CASE WHEN o.name = 'SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO'
            THEN CASE WHEN CHARINDEX('script 24', OBJECT_DEFINITION(o.object_id)) > 0 THEN 'SIM' ELSE 'NAO' END END AS tem_ajuste_script24
  FROM sys.objects o
 WHERE o.name IN ('SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO', 'SP_FIKON_ATUALIZA_CABECALHO_DEVOLUCAO_BKP_SCRIPT24')
 ORDER BY o.name;
GO
