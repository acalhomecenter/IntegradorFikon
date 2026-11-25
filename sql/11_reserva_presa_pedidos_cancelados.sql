/*
  11 - Reserva presa por pedido CANCELADO (Gemco)  -  13/11/2026
  Somente leitura (SELECT). Pode rodar na produção.
  Uma linha por filial + produto que tem reserva presa por pedido cancelado.

  Quando a reserva é considerada presa (as três condições juntas):
    1. Pedido cancelado com reserva não baixada:
       - o pedido está cancelado (MOV_PEDIDO.STATUS = 9), sem outro pedido com o mesmo número que não seja
         cancelado;
       - no extrato de estoque (MOV_EXTRATOPROD) a reserva que ele fez naquela filial + produto não foi
         baixada: a soma de (RESFISPOS - RESFIS) dos movimentos do pedido é positiva.
    2. A reserva do produto não zerou depois que o pedido reservou. Se zerou, ela já foi limpa.
    3. A reserva atual (CAD_PRODLOC.RESFIS) é maior que a quantidade nos pedidos em aberto da filial
       (MOV_ITPED com FILORIG = filial e STATUS 1, 2, 3, 4, 5 ou 8; quantidade - faturado).
       Ou seja, há reserva que nenhum pedido vivo explica.

  Colunas:
    QT_RESERVADA            reserva atual do produto na filial
    QT_EM_PEDIDOS_ABERTOS   quanto dela os pedidos em aberto explicam
    QT_RESERVA_PRESA        menor valor entre o saldo dos pedidos cancelados e (reserva - pedidos em aberto)
    CMUP                    da filial; se zero, o da filial 8 (CD)
    CUSTO_RESERVA_PRESA     QT_RESERVA_PRESA x CMUP
    ULTIMO_PEDIDO_CANCELADO o cancelado mais recente que reservou e não baixou
    QT_PEDIDOS_CANCELADOS   quantos pedidos cancelados deixaram reserva no produto

  Antes de liberar uma reserva, confira o produto na tela de estoque do Gemco. A regra usa o extrato, que
  não registra ajustes feitos fora das rotinas.

  Desempenho: varre o extrato de estoque uma vez (cerca de 14 milhões de linhas), em torno de 20 a 30 s.
*/
SET NOCOUNT ON;

-- Filtros opcionais: deixe NULL para todas as filiais / todos os produtos
DECLARE @filial    numeric(5)  = NULL;   -- ex.: 8
DECLARE @coditprod numeric(10) = NULL;   -- ex.: 63811

WITH reserva AS (
    SELECT pl.CODFIL, pl.CODITPROD, SUM(pl.RESFIS) AS QT_RESERVADA
      FROM dbo.CAD_PRODLOC pl WITH (NOLOCK)
     WHERE pl.RESFIS > 0
       AND (@filial IS NULL OR pl.CODFIL = @filial)
       AND (@coditprod IS NULL OR pl.CODITPROD = @coditprod)
     GROUP BY pl.CODFIL, pl.CODITPROD
),
ext AS (   -- movimentos que mexeram na reserva dos produtos acima
    SELECT e.CODFIL, e.CODITPROD, e.NUMPED, e.DATAHORAID, e.RESFIS, e.RESFISPOS
      FROM dbo.MOV_EXTRATOPROD e WITH (NOLOCK)
      JOIN reserva r ON r.CODFIL = e.CODFIL AND r.CODITPROD = e.CODITPROD
     WHERE e.RESFISPOS <> e.RESFIS
),
zerou AS (   -- última vez que a reserva do produto zerou
    SELECT CODFIL, CODITPROD, MAX(DATAHORAID) AS DT_ULT_ZERO
      FROM ext WHERE RESFISPOS <= 0
     GROUP BY CODFIL, CODITPROD
),
saldo_ped AS (   -- saldo de reserva que cada pedido deixou
    SELECT CODFIL, CODITPROD, NUMPED,
           SUM(RESFISPOS - RESFIS) AS SALDO_PEDIDO,
           MAX(CASE WHEN RESFISPOS > RESFIS THEN DATAHORAID END) AS DT_RESERVA
      FROM ext
     WHERE ISNULL(NUMPED, 0) <> 0
     GROUP BY CODFIL, CODITPROD, NUMPED
    HAVING SUM(RESFISPOS - RESFIS) > 0
),
cancelados AS (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY s.CODFIL, s.CODITPROD ORDER BY s.DT_RESERVA DESC) AS rn,
           COUNT(*)            OVER (PARTITION BY s.CODFIL, s.CODITPROD) AS QT_PEDIDOS_CANCELADOS,
           SUM(s.SALDO_PEDIDO) OVER (PARTITION BY s.CODFIL, s.CODITPROD) AS SALDO_CANCELADOS
      FROM saldo_ped s
      LEFT JOIN zerou z ON z.CODFIL = s.CODFIL AND z.CODITPROD = s.CODITPROD
     WHERE (z.DT_ULT_ZERO IS NULL OR s.DT_RESERVA > z.DT_ULT_ZERO)
       AND EXISTS     (SELECT 1 FROM dbo.MOV_PEDIDO x WITH (NOLOCK) WHERE x.NUMPEDVEN = s.NUMPED AND x.STATUS = 9)
       AND NOT EXISTS (SELECT 1 FROM dbo.MOV_PEDIDO y WITH (NOLOCK) WHERE y.NUMPEDVEN = s.NUMPED AND y.STATUS <> 9)
),
final AS (
    SELECT c.*, r.QT_RESERVADA,
           ISNULL(ab.QT_ABERTO, 0) AS QT_EM_PEDIDOS_ABERTOS,
           r.QT_RESERVADA - ISNULL(ab.QT_ABERTO, 0) AS QT_SEM_PEDIDO,
           itp.CODPROD
      FROM cancelados c
      JOIN reserva r ON r.CODFIL = c.CODFIL AND r.CODITPROD = c.CODITPROD
      JOIN dbo.CAD_ITPROD itp WITH (NOLOCK) ON itp.CODITPROD = c.CODITPROD
     OUTER APPLY (SELECT SUM(i.QTCOMP - ISNULL(i.QTFAT, 0)) AS QT_ABERTO
                    FROM dbo.MOV_ITPED i WITH (NOLOCK)
                   WHERE i.FILORIG = c.CODFIL AND i.CODITPROD = c.CODITPROD
                     AND i.STATUS IN (1, 2, 3, 4, 5, 8)) ab
     WHERE c.rn = 1
)
SELECT f.CODFIL                                                   AS FILIAL_RESERVA,
       f.CODITPROD,
       pro.DESCRICAO,
       f.QT_RESERVADA,
       f.QT_EM_PEDIDOS_ABERTOS,
       q.QT_RESERVA_PRESA,
       COALESCE(NULLIF(vf.CMUP, 0), v8.CMUP, 0)                   AS CMUP,
       CAST(q.QT_RESERVA_PRESA * COALESCE(NULLIF(vf.CMUP, 0), v8.CMUP, 0) AS numeric(15,2)) AS CUSTO_RESERVA_PRESA,
       f.NUMPED                                                   AS ULTIMO_PEDIDO_CANCELADO,
       p.CODFIL                                                   AS FILIAL_PEDIDO,
       f.DT_RESERVA                                               AS DT_ULTIMO_PEDIDO,
       p.DTCANCELA                                                AS DT_CANCELAMENTO,
       f.SALDO_PEDIDO                                             AS QT_RESERVADA_PELO_PEDIDO,
       f.QT_PEDIDOS_CANCELADOS
  FROM final f
  JOIN dbo.CAD_PROD pro WITH (NOLOCK) ON pro.CODPROD = f.CODPROD
  LEFT JOIN dbo.VEN_PRODFIL vf WITH (NOLOCK) ON vf.CODFIL = f.CODFIL AND vf.CODPROD = f.CODPROD
  LEFT JOIN dbo.VEN_PRODFIL v8 WITH (NOLOCK) ON v8.CODFIL = 8 AND v8.CODPROD = f.CODPROD
 CROSS APPLY (SELECT CASE WHEN f.SALDO_CANCELADOS < f.QT_SEM_PEDIDO THEN f.SALDO_CANCELADOS ELSE f.QT_SEM_PEDIDO END AS QT_RESERVA_PRESA) q
 OUTER APPLY (SELECT TOP 1 x.CODFIL, x.DTCANCELA
                FROM dbo.MOV_PEDIDO x WITH (NOLOCK)
               WHERE x.NUMPEDVEN = f.NUMPED AND x.STATUS = 9
               ORDER BY x.DTPEDIDO DESC) p
 WHERE f.QT_SEM_PEDIDO > 0
 ORDER BY CUSTO_RESERVA_PRESA DESC
OPTION (RECOMPILE);
