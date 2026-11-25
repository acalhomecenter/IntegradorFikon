-- Comportamento fiscal do cliente enviado à Fikon: o cliente com inscrição estadual ia como 'Contrinuinte'
-- (erro de digitação), texto que não existe na Fikon, e o cliente ficava sem Comportamento Fiscal.
-- Passa a ir como 'Comércio', nome exato do Comportamento Fiscal na Fikon (o mesmo texto que as
-- procedures de fornecedor já usam).
USE dbgemco;
GO

-- C120444
ALTER PROC [dbo].[SP_FIKON_INSERT_CLIENTE] 

as
--C535934
Select top 20  'C'+convert(varchar,cli.codcli) as 'CODIGO',
cli.NOMCLI as 'Nome',
cli.RESCLI as Apelido,
case when cli.natjur='J' then 'Pessoa Juridica' else 'Pessoa Fisica' end as 'Classe',
'' as 'Estabelecimento',
ecli.cep as 'Cep',
ltrim(rtrim(isnull(ecli.pais,''))) as 'Pais',
ltrim(rtrim(isnull(ecli.Estado,''))) as 'Uf',
ltrim(rtrim(isnull(ecli.cidade,''))) as 'Cidade',
ltrim(rtrim(isnull(ecli.bairro,''))) as 'Bairro',
ltrim(rtrim(isnull(lg.descricao,''))) as 'TpLogradouro',
ltrim(rtrim(replace(replace(replace(replace(replace(replace(replace(replace(ecli.ENDERECO, 'RUA ',''),'AVENIDA ',''),'AV ',''),'RODOVIA ',''),'AV. ',''),'R.',''),'AV.',''),'R. ',''))) as 'Logradouro',
ltrim(rtrim(isnull(convert(varchar,ecli.numero),''))) as 'Numero',
ltrim(rtrim(isnull(ecli.complemento,''))) as 'Complemento',
ltrim(rtrim(isnull(ecli.REFER,''))) as 'Referencia',
ltrim(rtrim(isnull(cli.naturalidade,''))) as 'Naturalidade',
'' as 'Nacionalidade',
isnull(isnull(ecli.dddfone1,ecli.dddfone2),'')+isnull(isnull(ecli.fone1,ecli.fone2),'') as Fone,
isnull(ecli.dddcel,'')+isnull(ecli.FONECEL,'') as Celular,
case when ecli.e_mail like '%@%' then isnull(ecli.e_mail,'') else '' end email,
case when cli.natjur = 'F' then replicate('0',11-len(cli.CGCCPF))+RTRIM(LTRIM(cli.CGCCPF)) else replicate('0',14-len(cli.CGCCPF))+RTRIM(LTRIM(cli.CGCCPF)) end  as 'CGCCPF',
case when ecli.tpinsc ='E' then INSCR else '' end  as 'InscEstad', 
case when ecli.tpinsc ='M' then INSCR else '' end  as 'InscMunic',
convert(varchar,cli.dtnasc,103) as Nascimento,
-- MODIFICAR QUANFO FOR PESSOA JURIDICA
case when ecli.TPINSC= 'E' then 'Comércio' else 'Não Contribuinte' end as 'CompFiscal',
dbAplicativos.dbo.udf_TitleCase(comp.obsgerais) as obsgerais
from cad_cliente cli 
inner join CAD_ENDCLI ecli on
cli.codcli=ecli.codcli 
and ecli.codend=0
and cli.codcli<>0
and cli.status<>9
and ecli.cep>=0
--and cli.CGCCPF='67208177368'
and cli.CGCCPF not in (
select CGCCPF from cad_cliente
where status<>9
group by CGCCPF 
having count(*) > 1)
left join dbgemco..cad_logradouro lg on
lg.codlograd=ecli.codlograd
left join dbgemco..cad_cliente_compl comp on
comp.codcli=cli.codcli
where 1=1
and (cli.codcli in (select codcli from dbgemco..fikon_cad_cliente where status='P' and tipo='I' )
or cli.codcli in (select codcli from dbgemco..fikon_cad_end_cliente where status='P' and tipo='I' ))
--and cli.codcli=560135
and cli.cgccpf not  in ('00024341070363','00041597591300','00042593948353','00075441462353','00004022885483','00061395501300','00037184288300',
'00016955331353','00064585204334','00015381501315','11111111111111',
'7201916000159',
'7201916000230',
'7201916000310',
'7201916000582',
'7201916000825',
'7201916000906',
'7201916001040',
'7201916001120',
'7201916001201',
'7201916001392',
'7201916001473',
'7201916001554',
'7201916001635')
order by cli.codcli asc
GO

-- C120444
ALTER PROC [dbo].[SP_FIKON_INSERT_CLIENTE_CARGA] 

as
--C535934
Select top 1000  'C'+convert(varchar,cli.codcli) as 'CODIGO',
cli.NOMCLI as 'Nome',
cli.RESCLI as Apelido,
case when cli.natjur='J' then 'Pessoa Juridica' else 'Pessoa Fisica' end as 'Classe',
'' as 'Estabelecimento',
ecli.cep as 'Cep',
ltrim(rtrim(isnull(ecli.pais,''))) as 'Pais',
ltrim(rtrim(isnull(ecli.Estado,''))) as 'Uf',
ltrim(rtrim(isnull(ecli.cidade,''))) as 'Cidade',
ltrim(rtrim(isnull(ecli.bairro,''))) as 'Bairro',
ltrim(rtrim(isnull(lg.descricao,''))) as 'TpLogradouro',
ltrim(rtrim(replace(replace(replace(replace(replace(replace(replace(replace(ecli.ENDERECO, 'RUA ',''),'AVENIDA ',''),'AV ',''),'RODOVIA ',''),'AV. ',''),'R.',''),'AV.',''),'R. ',''))) as 'Logradouro',
ltrim(rtrim(isnull(convert(varchar,ecli.numero),''))) as 'Numero',
ltrim(rtrim(isnull(ecli.complemento,''))) as 'Complemento',
ltrim(rtrim(isnull(ecli.REFER,''))) as 'Referencia',
ltrim(rtrim(isnull(cli.naturalidade,''))) as 'Naturalidade',
'' as 'Nacionalidade',
isnull(isnull(ecli.dddfone1,ecli.dddfone2),'')+isnull(isnull(ecli.fone1,ecli.fone2),'') as Fone,
isnull(ecli.dddcel,'')+isnull(ecli.FONECEL,'') as Celular,
case when ecli.e_mail like '%@%' then isnull(ecli.e_mail,'') else '' end email,
case when cli.natjur = 'F' then replicate('0',11-len(cli.CGCCPF))+RTRIM(LTRIM(cli.CGCCPF)) else replicate('0',14-len(cli.CGCCPF))+RTRIM(LTRIM(cli.CGCCPF)) end  as 'CGCCPF',
case when ecli.tpinsc ='E' then INSCR else '' end  as 'InscEstad', 
case when ecli.tpinsc ='M' then INSCR else '' end  as 'InscMunic',
convert(varchar,cli.dtnasc,103) as Nascimento,
-- MODIFICAR QUANFO FOR PESSOA JURIDICA
case when ecli.TPINSC= 'E' then 'Comércio' else 'Não Contribuinte' end as 'CompFiscal',
dbAplicativos.dbo.udf_TitleCase(comp.obsgerais) as obsgerais
from cad_cliente cli 
inner join CAD_ENDCLI ecli on
cli.codcli=ecli.codcli 
and ecli.codend=0
and cli.codcli<>0
and cli.status<>9
and ecli.cep>0
--and cli.CGCCPF='67208177368'
and cli.CGCCPF not in (
select CGCCPF from cad_cliente
where status<>9
group by CGCCPF 
having count(*) > 1)
left join dbgemco..cad_logradouro lg on
lg.codlograd=ecli.codlograd
left join dbgemco..cad_cliente_compl comp on
comp.codcli=cli.codcli
where 1=1
--and (cli.codcli in (select codcli from dbgemco..fikon_cad_cliente where status='P' and tipo='I' )
--or cli.codcli in (select codcli from dbgemco..fikon_cad_end_cliente where status='P' and tipo='I' ))
--and cli.codcli=560398
and cli.cgccpf not  in ('00024341070363','00041597591300','00042593948353','00075441462353','00004022885483','00061395501300','00037184288300',
'00016955331353','00064585204334','00015381501315','11111111111111',
'7201916000159',
'7201916000230',
'7201916000310',
'7201916000582',
'7201916000825',
'7201916000906',
'7201916001040',
'7201916001120',
'7201916001201',
'7201916001392',
'7201916001473',
'7201916001554',
'7201916001635')
order by cli.codcli desc
GO
