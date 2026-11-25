-- Remove as junções com cad_palletfilprod (CODFIL = 5) e cad_codbarra das procedures de produto da
-- integração Fikon. Nenhuma das duas é usada em campo do SELECT (o EAN está comentado) e ambas
-- multiplicam a linha do item: pallet com várias linhas na filial 5 (até 6 vezes) e código de barras
-- com o mesmo tsultalt. O mesmo produto era enviado várias vezes à Fikon no mesmo ciclo.
-- Conferência antes/depois: SELECT itp.coditprod, COUNT(*) ... GROUP BY itp.coditprod HAVING COUNT(*) > 1
USE dbgemco;
GO

ALTER PROC [dbo].[SP_FIKON_INSERT_PRODUTOS]
as

select top 20
convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'CODIGO',
ltrim(rtrim(concat(pro.descricao,' ',replace(esp.DESCRES,'.',''),' ',replace(cor.DESCRES,'.','')))) as 'NOME',
concat(aux.prefixo,' ',
replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(fam.descricao,'P TOALHAS','PORTA TOALHAS'),
'ACESS LOUCAS','ACESSORIOS LOUCAS'),
'P SHAMPOO','PORTA SHAMPOO'),
'AQUECEDORES..','AQUECEDORES'),
'CABIDES.','CABIDES'),
'PRATELEIRA BANH','PRATELEIRA BANHEIRO'),
'CAIXAS D´AGUA', 'CAIXAS DE AGUA'),
'TANQUES D´AGUA', 'TANQUES DE AGUA'),
'BOMBAS D´ÁGUA', 'BOMBAS DE AGUA'),
'CINTAS.','CINTAS'),
'CALHAS..','CALHAS'),
'ACESS UTL.','ACESS UTL'),
'PIAS.','PIAS'),
'LAVATORIOS..','LAVATORIOS'),
'NICHOS..','NICHOS'),
'SUPORTE..','SUPORTE'),
'CABOS UTL.','CABOS UTL'),
'FECHOS UTL.','FECHOS UTL'),
'PAS UTL.', 'PAS UTL'),
'CAMPAINHA ELETR','CAMPAINHA ELETRICA'),
'ACESS. ELETRICOS', 'ACESSORIOS ELETRICOS'),
'ADAPTADORES ELET', 'ADAPTADORES ELETRICOS'),
'FITAS ELET', 'FITAS ELETRICAS'),
'PLUGS ELETR', 'PLUGS ELETRICOS')

) as 'CLASSE', 
concat(substring(pro.ncm,1,4),'.',substring(pro.ncm,5,2),'.',substring(pro.ncm,7,2)) as 'CLFISCAL',
replace(replace(emb.unidmenor,'MT','M'),'LT','L') as 'UNIDMEDIDA',
case when pro.codicms in (4) then '2' else '0' end as Procedencia,
replace(f.codforne,'DIVERSOS','Fornecedor Genérico') as 'FABRICANTE',
itp.coditforn as 'REFFABRICA',
f.fantasia as 'MARCA',
replace(g.descricao,'.','') as 'MODELO',
'' as 'COLECAO',
case when pro.codlinha=1 then replace(sb.descricao,'.','') else
replace(cor.descricao,'.','') end as 'COR',
case when itp.codlinha  in (1,8) then  replace(cap.descricao,'.','') else '' end as 'TAMANHO', 
isnull(emb.qtembmovimvenda,1) as 'QdePorvol',
isnull(emb.qtembmovim,1) as 'QdeporvolCompra',
case when pco.codsitprod = 'IN' then convert(varchar, cast(getdate() as date) ,103) else null end as 'ForaDeLinha',
case when pco.codsitprod = 'IN' then '' else '' end as 'ForadeLinhaInfo',
'' as 'INATIVO',
'' as 'INATIVADOR',
'' as 'MATERIAL',
'' as 'REFPRINCIPAL',
ltrim(rtrim(concat(pro.descricao,' ',replace(esp.descricao,'.',''),' ',replace(cor.descricao,'.',''))))  as 'DESCRICAOGENERICA' ,
'' as 'CEST',
'' as 'TpMedicamento',
'' as 'OutrasCaracterísticas',
'' as 'Validade',
'' 'Localizaçãofísica',
pro.codprod as codprod,
emb.altura as 'ALTURA',
emb.largura as 'LARGURA',
emb.comp as 'COMPRIMENTO',
pro.pesounit as PESBRUUNID,
pro.pesoliq as PESLIQUNID

-- Ate aqui parametros existentes na importação

--convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'REFERENCIAPRINCIPAL',
--bar.codbarra as 'EAN',
--case when itp.codlinha not in (1,8) then  replace(cap.descricao,'.','') else '' end as 'CAPACIDADE',

--'' as 'VOLUME',
--pro.pesounit as PESBRUUNID,
--pro.pesoliq as PESLIQUNID
from cad_prod pro 
inner join cad_itprod itp on
pro.codprod=itp.codprod 
inner join cad_forne f on
f.CODFORNE=pro.codforne
inner join cad_linha l on
l.codlinha=pro.codlinha
inner join cad_familia fam on
fam.codfam=pro.codfam
inner join cad_grupo g on
pro.CODGRUPO=g.codgrupo
and pro.codfam=g.codfam
inner join cad_subgrup sb on
sb.codfam=pro.codfam
and sb.codsubgp=pro.codsubgp
inner join cad_espec esp on
esp.codfam=pro.codfam
and esp.especific=itp.especific
inner join cad_cor cor on
cor.codcor=itp.codcor
inner join cad_embal emb on
emb.codembal=0
and emb.codprod=pro.codprod
inner join cad_preco pco on
pco.coditprod=itp.coditprod
and pco.codfil=8
and pco.codembal=0
and pco.codsitprod not in ('FL','IC')
left join cad_capac cap on
cap.codfam=pro.codfam
and cap.codcapac=pro.codcapac
left join com_compr cp on
cp.codcomp=pro.codgercomp
left join dbHub..AUX_IMPORT_PRODUTO aux on
aux.linha=l.descricao
where 1=1
and pro.codprod in (select codprod from fikon_cad_prod where status='P' and tipo='I')
--and itp.codlinha > 9
and itp.codlinha not in (16,39,42,50)
and itp.CODITPROD not in (43943)
GO

ALTER PROC [dbo].[SP_FIKON_ALTER_PRODUTOS]
as

select top 20
convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'CODIGO',
ltrim(rtrim(concat(pro.descricao,' ',replace(esp.DESCRES,'.',''),' ',replace(cor.DESCRES,'.','')))) as 'NOME',
concat(aux.prefixo,' ',
replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(fam.descricao,'P TOALHAS','PORTA TOALHAS'),
'ACESS LOUCAS','ACESSORIOS LOUCAS'),
'P SHAMPOO','PORTA SHAMPOO'),
'AQUECEDORES..','AQUECEDORES'),
'CABIDES.','CABIDES'),
'PRATELEIRA BANH','PRATELEIRA BANHEIRO'),
'CAIXAS D´AGUA', 'CAIXAS DE AGUA'),
'TANQUES D´AGUA', 'TANQUES DE AGUA'),
'BOMBAS D´ÁGUA', 'BOMBAS DE AGUA'),
'CINTAS.','CINTAS'),
'CALHAS..','CALHAS'),
'ACESS UTL.','ACESS UTL'),
'PIAS.','PIAS'),
'LAVATORIOS..','LAVATORIOS'),
'NICHOS..','NICHOS'),
'SUPORTE..','SUPORTE'),
'CABOS UTL.','CABOS UTL'),
'FECHOS UTL.','FECHOS UTL'),
'PAS UTL.', 'PAS UTL'),
'CAMPAINHA ELETR','CAMPAINHA ELETRICA'),
'ACESS. ELETRICOS', 'ACESSORIOS ELETRICOS'),
'ADAPTADORES ELET', 'ADAPTADORES ELETRICOS'),
'FITAS ELET', 'FITAS ELETRICAS'),
'PLUGS ELETR', 'PLUGS ELETRICOS')

) as 'CLASSE', 
concat(substring(pro.ncm,1,4),'.',substring(pro.ncm,5,2),'.',substring(pro.ncm,7,2)) as 'CLFISCAL',
replace(replace(emb.unidmenor,'MT','M'),'LT','L') as 'UNIDMEDIDA',
case when pro.codicms in (4) then '2' else '0' end as Procedencia,
replace(f.codforne,'DIVERSOS','Fornecedor Genérico') as 'FABRICANTE',
itp.coditforn as 'REFFABRICA',
f.fantasia as 'MARCA',
replace(g.descricao,'.','') as 'MODELO',
'' as 'COLECAO',
case when pro.codlinha=1 then replace(sb.descricao,'.','') else
replace(cor.descricao,'.','') end as 'COR',
case when itp.codlinha  in (1,8) then  replace(cap.descricao,'.','') else '' end as 'TAMANHO', 
isnull(emb.qtembmovimvenda,1) as 'QdePorvol',
isnull(emb.qtembmovim,1) as 'QdeporvolCompra',
case when pco.codsitprod = 'IN' then convert(varchar, cast(getdate() as date) ,103) else null end as 'ForaDeLinha',
case when pco.codsitprod = 'IN' then '' else '' end as 'ForadeLinhaInfo',
'' as 'INATIVO',
'' as 'INATIVADOR',
'' as 'MATERIAL',
'' as 'REFPRINCIPAL',
ltrim(rtrim(concat(pro.descricao,' ',replace(esp.descricao,'.',''),' ',replace(cor.descricao,'.',''))))  as 'DESCRICAOGENERICA' ,
'' as 'CEST',
'' as 'TpMedicamento',
'' as 'OutrasCaracterísticas',
'' as 'Validade',
'' 'Localizaçãofísica',
pro.codprod as codprod,
emb.altura as 'ALTURA',
emb.largura as 'LARGURA',
emb.comp as 'COMPRIMENTO',
pro.pesounit as PESBRUUNID,
pro.pesoliq as PESLIQUNID


-- Ate aqui parametros existentes na importação

--convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'REFERENCIAPRINCIPAL',
--bar.codbarra as 'EAN',
--case when itp.codlinha not in (1,8) then  replace(cap.descricao,'.','') else '' end as 'CAPACIDADE',

--'' as 'VOLUME',

--pro.pesoliq as PESLIQUNID
from cad_prod pro 
inner join cad_itprod itp on
pro.codprod=itp.codprod 
inner join cad_forne f on
f.CODFORNE=pro.codforne
inner join cad_linha l on
l.codlinha=pro.codlinha
inner join cad_familia fam on
fam.codfam=pro.codfam
inner join cad_grupo g on
pro.CODGRUPO=g.codgrupo
and pro.codfam=g.codfam
inner join cad_subgrup sb on
sb.codfam=pro.codfam
and sb.codsubgp=pro.codsubgp
inner join cad_espec esp on
esp.codfam=pro.codfam
and esp.especific=itp.especific
inner join cad_cor cor on
cor.codcor=itp.codcor
inner join cad_embal emb on
emb.codembal=0
and emb.codprod=pro.codprod
inner join cad_preco pco on
pco.coditprod=itp.coditprod
and pco.codfil=8
and pco.codembal=0
and pco.codsitprod not in ('FL','IC')
left join cad_capac cap on
cap.codfam=pro.codfam
and cap.codcapac=pro.codcapac
left join com_compr cp on
cp.codcomp=pro.codgercomp
left join dbHub..AUX_IMPORT_PRODUTO aux on
aux.linha=l.descricao
where 1=1
and pro.codprod in (select codprod from fikon_cad_prod where status='P' and tipo='A')
--and itp.codlinha > 9
and itp.codlinha not in (16,39,42,50)
and itp.CODITPROD not in (43943)
GO

ALTER PROC [dbo].[SP_FIKON_ALTER_PRODUTOS_TODOS]
as

select
convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'CODIGO',
ltrim(rtrim(concat(pro.descricao,' ',replace(esp.DESCRES,'.',''),' ',replace(cor.DESCRES,'.','')))) as 'NOME',
concat(aux.prefixo,' ',
replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(fam.descricao,'P TOALHAS','PORTA TOALHAS'),
'ACESS LOUCAS','ACESSORIOS LOUCAS'),
'P SHAMPOO','PORTA SHAMPOO'),
'AQUECEDORES..','AQUECEDORES'),
'CABIDES.','CABIDES'),
'PRATELEIRA BANH','PRATELEIRA BANHEIRO'),
'CAIXAS D´AGUA', 'CAIXAS DE AGUA'),
'TANQUES D´AGUA', 'TANQUES DE AGUA'),
'BOMBAS D´ÁGUA', 'BOMBAS DE AGUA'),
'CINTAS.','CINTAS'),
'CALHAS..','CALHAS'),
'ACESS UTL.','ACESS UTL'),
'PIAS.','PIAS'),
'LAVATORIOS..','LAVATORIOS'),
'NICHOS..','NICHOS'),
'SUPORTE..','SUPORTE'),
'CABOS UTL.','CABOS UTL'),
'FECHOS UTL.','FECHOS UTL'),
'PAS UTL.', 'PAS UTL'),
'CAMPAINHA ELETR','CAMPAINHA ELETRICA'),
'ACESS. ELETRICOS', 'ACESSORIOS ELETRICOS'),
'ADAPTADORES ELET', 'ADAPTADORES ELETRICOS'),
'FITAS ELET', 'FITAS ELETRICAS'),
'PLUGS ELETR', 'PLUGS ELETRICOS')

) as 'CLASSE', 
concat(substring(pro.ncm,1,4),'.',substring(pro.ncm,5,2),'.',substring(pro.ncm,7,2)) as 'CLFISCAL',
replace(replace(emb.unidmenor,'MT','M'),'LT','L') as 'UNIDMEDIDA',
case when pro.codicms in (4) then '2' else '0' end as Procedencia,
replace(f.codforne,'DIVERSOS','Fornecedor Genérico') as 'FABRICANTE',
itp.coditforn as 'REFFABRICA',
f.fantasia as 'MARCA',
replace(g.descricao,'.','') as 'MODELO',
'' as 'COLECAO',
case when pro.codlinha=1 then replace(sb.descricao,'.','') else
replace(cor.descricao,'.','') end as 'COR',
case when itp.codlinha  in (1,8) then  replace(cap.descricao,'.','') else '' end as 'TAMANHO', 
isnull(emb.qtembmovimvenda,1) as 'QdePorvol',
isnull(emb.qtembmovim,1) as 'QdeporvolCompra',
case when pco.codsitprod = 'IN' then convert(varchar, cast(getdate() as date) ,103) else null end as 'ForaDeLinha',
case when pco.codsitprod = 'IN' then '' else '' end as 'ForadeLinhaInfo',
'' as 'INATIVO',
'' as 'INATIVADOR',
'' as 'MATERIAL',
'' as 'REFPRINCIPAL',
ltrim(rtrim(concat(pro.descricao,' ',replace(esp.descricao,'.',''),' ',replace(cor.descricao,'.',''))))  as 'DESCRICAOGENERICA' ,
'' as 'CEST',
'' as 'TpMedicamento',
'' as 'OutrasCaracterísticas',
'' as 'Validade',
'' 'Localizaçãofísica',
pro.codprod as codprod,
emb.altura as 'ALTURA',
emb.largura as 'LARGURA',
emb.comp as 'COMPRIMENTO',
pro.pesounit as PESBRUUNID,
pro.pesoliq as PESLIQUNID


-- Ate aqui parametros existentes na importação

--convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'REFERENCIAPRINCIPAL',
--bar.codbarra as 'EAN',
--case when itp.codlinha not in (1,8) then  replace(cap.descricao,'.','') else '' end as 'CAPACIDADE',

--'' as 'VOLUME',

--pro.pesoliq as PESLIQUNID
from cad_prod pro 
inner join cad_itprod itp on
pro.codprod=itp.codprod 
inner join cad_forne f on
f.CODFORNE=pro.codforne
inner join cad_linha l on
l.codlinha=pro.codlinha
inner join cad_familia fam on
fam.codfam=pro.codfam
inner join cad_grupo g on
pro.CODGRUPO=g.codgrupo
and pro.codfam=g.codfam
inner join cad_subgrup sb on
sb.codfam=pro.codfam
and sb.codsubgp=pro.codsubgp
inner join cad_espec esp on
esp.codfam=pro.codfam
and esp.especific=itp.especific
inner join cad_cor cor on
cor.codcor=itp.codcor
inner join cad_embal emb on
emb.codembal=0
and emb.codprod=pro.codprod
inner join cad_preco pco on
pco.coditprod=itp.coditprod
and pco.codfil=8
and pco.codembal=0
and pco.codsitprod not in ('FL','IC')
left join cad_capac cap on
cap.codfam=pro.codfam
and cap.codcapac=pro.codcapac
left join com_compr cp on
cp.codcomp=pro.codgercomp
left join dbHub..AUX_IMPORT_PRODUTO aux on
aux.linha=l.descricao
where 1=1
and itp.coditprod <> 16478
--and pro.codprod=65027
and itp.codlinha >=  9
and itp.codlinha not in (16,39,42,50)
and itp.CODITPROD not in (43943)
GO
