-- Códigos do produto enviados à Fikon: deixa de mandar os códigos de barras das embalagens 1 e 2
-- (caixa/palete). Eles iam como Gtin 13/14 do produto, sem quantidade: no caixa da Fikon a caixa era
-- vendida como 1 unidade e a NF-e podia sair com o GTIN da caixa ou com código interno.
-- Continua mandando a Referência do Fornecedor e o código de barras mais recente da unidade.
USE dbgemco;
GO
ALTER PROC [dbo].[SP_FIKON_CONSULTA_CODIGOS]  
@recurso numeric(12,0)
as

select
convert(varchar,max(itp.coditforn)) as 'Codigo',
convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'Recurso',
'Referência do Fornecedor' as 'Classificacao',
replace(max(f.CODFORNE),'DIVERSOS','Fornecedor Genérico') as 'Fornecedor'
from cad_prod pro inner join cad_itprod itp on
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
left join cad_codbarra bar on
bar.codprod=pro.codprod
and bar.codembal=emb.codembal
and len(bar.codbarra)>6 
and bar.tsultalt = (select max(tsultalt) from cad_codbarra
                     where codprod=pro.codprod and codembal=0 
					 and len(codbarra)>6 )
left join cad_capac cap on
cap.codfam=pro.codfam
and cap.codcapac=pro.codcapac
left join cad_palletfilprod pp on
pp.CODITPROD=itp.CODITPROD
and pp.CODFIL=5
left join com_compr cp on
cp.codcomp=pro.codgercomp
left join dbHub..AUX_IMPORT_PRODUTO aux on
aux.linha=l.descricao
where 1=1
and itp.CODITPROD = LEFT(convert(varchar,@recurso), LEN(@recurso) - 1)
and itp.codlinha not in (16,39,42,50)
and itp.CODITPROD not in (43943)
and itp.coditforn is not null
group by itp.coditprod,itp.digitprod

union all

select
convert(varchar,max(bar.codbarra)) as 'Codigo',
convert(varchar,itp.coditprod) + convert(varchar,itp.digitprod) as 'Recurso',
case when len(max(bar.codbarra))=14 then 'Gtin 14'   else 'Gtin 13' end as 'Classificacao',
replace(max(f.RAZSOC),'DIVERSOS','Fornecedor Genérico') as 'Fornecedor'
from cad_prod pro inner join cad_itprod itp on
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
left join cad_codbarra bar on
bar.codprod=pro.codprod
and bar.codembal=emb.codembal
and len(bar.codbarra)>6 
and bar.tsultalt = (select max(tsultalt) from cad_codbarra
                     where codprod=pro.codprod  and codembal=0
					 and len(codbarra)>6 )
left join cad_capac cap on
cap.codfam=pro.codfam
and cap.codcapac=pro.codcapac
left join cad_palletfilprod pp on
pp.CODITPROD=itp.CODITPROD
and pp.CODFIL=5
left join com_compr cp on
cp.codcomp=pro.codgercomp
left join dbHub..AUX_IMPORT_PRODUTO aux on
aux.linha=l.descricao
where 1=1
and itp.CODITPROD = LEFT(convert(varchar,@recurso), LEN(@recurso) - 1)
and itp.codlinha not in (16,39,42,50)
and itp.CODITPROD not in (43943)
group by itp.coditprod,itp.digitprod
GO
