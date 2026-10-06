-- 04_products.sql
-- What sells, in which sizes, and how concentrated is revenue?
.headers on
.mode column

SELECT category, count(DISTINCT style) AS styles,
       sum(CASE WHEN outcome = 'Shipped' THEN qty END) AS units_shipped,
       round(sum(net_revenue_inr) / 1e6, 2) AS net_inr_m,
       round(100.0 * sum(net_revenue_inr) / (SELECT sum(net_revenue_inr) FROM orders), 1) AS pct_of_revenue,
       round(sum(net_revenue_inr) / sum(CASE WHEN outcome = 'Shipped' THEN qty END), 0) AS revenue_per_unit,
       round(100.0 * sum(outcome = 'Cancelled') / count(*), 1) AS cancel_pct
FROM orders GROUP BY category ORDER BY net_inr_m DESC;

-- Revenue concentration by SKU decile (window function)
WITH sku_rev AS (
  SELECT sku, sum(net_revenue_inr) AS rev FROM orders GROUP BY sku HAVING rev > 0
),
ranked AS (SELECT sku, rev, ntile(10) OVER (ORDER BY rev DESC) AS decile FROM sku_rev)
SELECT decile, count(*) AS skus, round(sum(rev) / 1e6, 2) AS net_inr_m,
       round(100.0 * sum(rev) / (SELECT sum(rev) FROM sku_rev), 1) AS pct_of_revenue
FROM ranked GROUP BY decile;

-- Size curve: share of shipped units by size
SELECT size, sum(qty) AS units,
       round(100.0 * sum(qty) / (SELECT sum(qty) FROM orders WHERE outcome = 'Shipped'), 1) AS pct_of_units
FROM orders WHERE outcome = 'Shipped' GROUP BY size ORDER BY units DESC;

-- Top 10 styles
SELECT style, category, sum(CASE WHEN outcome = 'Shipped' THEN qty END) AS units,
       round(sum(net_revenue_inr) / 1e6, 2) AS net_inr_m
FROM orders GROUP BY style ORDER BY net_inr_m DESC LIMIT 10;
