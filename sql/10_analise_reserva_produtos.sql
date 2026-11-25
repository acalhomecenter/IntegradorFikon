/*
  10 - Análise da reserva de produtos (Gemco)  -  13/11/2026
  Somente leitura (SELECT). Pode rodar na produção.

  De onde vem cada coluna:
    FILIAL_RESERVA, QT_RESERVADA
        CAD_PRODLOC.RESFIS (reserva física), somada por filial + produto (depósitos L e D juntos).
        Só reserva positiva. Para ver também as negativas, troque "RESFIS > 0" por "RESFIS <> 0".
    CODITPROD, DESCRICAO
        CAD_ITPROD -> CAD_PROD.DESCRICAO.
    CMUP, ORIGEM_CMUP
        CMUP da VEN_PRODFIL da própria filial da reserva. Quando é zero, usa o da filial 8 (CD).
        Hoje só a filial 8 mantém CMUP para quase todos os produtos.
    CUSTO_RESERVA
        QT_RESERVADA x CMUP.
    DT_ULTIMO_PEDIDO, ULTIMO_PEDIDO, QT_RESERVADA_PELO_PEDIDO
        Último movimento do extrato de estoque (MOV_EXTRATOPROD) que AUMENTOU a reserva do produto naquela
        filial (RESFISPOS > RESFIS): número do pedido, data/hora e quanto ele reservou.
        Sem movimento no extrato: último pedido em aberto (MOV_ITPED, status 1, 2, 3, 4, 5 ou 8) da filial
        de origem.
    FILIAL_PEDIDO, STATUS_PEDIDO
        Da MOV_PEDIDO. O pedido pode ser de outra loja que reservou no estoque desta filial (ex.: CD).
        Pedido que reservou e já está cancelado/faturado, e a reserva não baixou, merece conferência.
    ORIGEM_PEDIDO
        EXTRATO DE ESTOQUE, PEDIDO EM ABERTO ou NAO ENCONTRADO.

  Desempenho: varre o extrato de estoque uma vez (cerca de 14 milhões de linhas) e leva em torno de
  20 a 30 segundos. Evite rodar várias vezes seguidas no horário de pico.
*/
SET NOCOUNT ON;

-- Filtros opcionais: deixe NULL para todas as filiais / todos os produtos
DECLARE @filial    numeric(5)  = NULL;   -- ex.: 5
DECLARE @coditprod numeric(10) = NULL;   -- ex.: 83489

WITH reserva AS (
    SELECT pl.CODFIL, pl.CODITPROD, SUM(pl.RESFIS) AS QT_RESERVADA
      FROM dbo.CAD_PRODLOC pl WITH (NOLOCK)
     WHERE pl.RESFIS > 0
       AND (@filial IS NULL OR pl.CODFIL = @filial)
       AND (@coditprod IS NULL OR pl.CODITPROD = @coditprod)
     GROUP BY pl.CODFIL, pl.CODITPROD
),
ult_extrato AS (
    SELECT e.CODFIL, e.CODITPROD, e.NUMPED, e.DATAHORAID, e.RESFISPOS - e.RESFIS AS QT_RESERVOU,
           ROW_NUMBER() OVER (PARTITION BY e.CODFIL, e.CODITPROD ORDER BY e.DATAHORAID DESC) AS rn
      FROM dbo.MOV_EXTRATOPROD e WITH (NOLOCK)
      JOIN reserva r ON r.CODFIL = e.CODFIL AND r.CODITPROD = e.CODITPROD
     WHERE e.RESFISPOS > e.RESFIS
)
SELECT r.CODFIL                                                  AS FILIAL_RESERVA,
       r.CODITPROD,
       pro.DESCRICAO,
       r.QT_RESERVADA,
       COALESCE(NULLIF(vf.CMUP, 0), v8.CMUP, 0)                  AS CMUP,
       CASE WHEN ISNULL(vf.CMUP, 0) > 0 THEN 'FILIAL'
            WHEN ISNULL(v8.CMUP, 0) > 0 THEN 'CD (FILIAL 8)'
            ELSE 'SEM CMUP' END                                  AS ORIGEM_CMUP,
       CAST(r.QT_RESERVADA * COALESCE(NULLIF(vf.CMUP, 0), v8.CMUP, 0) AS numeric(15,2)) AS CUSTO_RESERVA,
       COALESCE(ue.DATAHORAID, ua.DTPEDIDO)                      AS DT_ULTIMO_PEDIDO,
       COALESCE(ue.NUMPED, ua.NUMPEDVEN)                         AS ULTIMO_PEDIDO,
       COALESCE(ue.QT_RESERVOU, ua.QTCOMP)                       AS QT_RESERVADA_PELO_PEDIDO,
       ped.CODFIL                                                AS FILIAL_PEDIDO,
       ped.STATUS                                                AS STATUS_PEDIDO,
       CASE WHEN ue.NUMPED IS NOT NULL THEN 'EXTRATO DE ESTOQUE'
            WHEN ua.NUMPEDVEN IS NOT NULL THEN 'PEDIDO EM ABERTO'
            ELSE 'NAO ENCONTRADO' END                            AS ORIGEM_PEDIDO
  FROM reserva r
  JOIN dbo.CAD_ITPROD itp WITH (NOLOCK) ON itp.CODITPROD = r.CODITPROD
  JOIN dbo.CAD_PROD pro WITH (NOLOCK) ON pro.CODPROD = itp.CODPROD
  LEFT JOIN dbo.VEN_PRODFIL vf WITH (NOLOCK) ON vf.CODFIL = r.CODFIL AND vf.CODPROD = itp.CODPROD
  LEFT JOIN dbo.VEN_PRODFIL v8 WITH (NOLOCK) ON v8.CODFIL = 8 AND v8.CODPROD = itp.CODPROD
  LEFT JOIN ult_extrato ue ON ue.CODFIL = r.CODFIL AND ue.CODITPROD = r.CODITPROD AND ue.rn = 1
 OUTER APPLY (SELECT TOP 1 i.NUMPEDVEN, i.DTPEDIDO, i.QTCOMP
                FROM dbo.MOV_ITPED i WITH (NOLOCK)
               WHERE ue.NUMPED IS NULL
                 AND i.FILORIG = r.CODFIL AND i.CODITPROD = r.CODITPROD
                 AND i.STATUS IN (1, 2, 3, 4, 5, 8)
               ORDER BY i.DTPEDIDO DESC, i.NUMPEDVEN DESC) ua
 OUTER APPLY (SELECT TOP 1 p.CODFIL, p.STATUS
                FROM dbo.MOV_PEDIDO p WITH (NOLOCK)
               WHERE p.NUMPEDVEN = COALESCE(ue.NUMPED, ua.NUMPEDVEN)
               ORDER BY p.DTPEDIDO DESC) ped
 ORDER BY CUSTO_RESERVA DESC
OPTION (RECOMPILE);   -- monta o plano com os filtros informados (rápido quando filtra filial/produto)
