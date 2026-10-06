-- 06_geography.sql
-- Where do orders come from, and does cancellation vary by state?
.headers on
.mode column

SELECT state, count(*) AS order_lines, round(sum(net_revenue_inr) / 1e6, 2) AS net_inr_m,
       round(100.0 * sum(net_revenue_inr) / (SELECT sum(net_revenue_inr) FROM orders), 1) AS pct_of_revenue,
       round(100.0 * sum(outcome = 'Cancelled') / count(*), 1) AS cancel_pct,
       round(100.0 * sum(fulfilment = 'Shipped by seller') / count(*), 1) AS seller_shipped_pct
FROM orders GROUP BY state ORDER BY net_inr_m DESC LIMIT 12;

-- Business (B2B) orders
SELECT CASE is_b2b WHEN 1 THEN 'Business' ELSE 'Consumer' END AS customer_type, count(*) AS order_lines,
       round(sum(net_revenue_inr) / 1e6, 2) AS net_inr_m,
       round(sum(net_revenue_inr) / sum(outcome = 'Shipped'), 0) AS net_per_shipped_line,
       round(100.0 * sum(outcome = 'Cancelled') / count(*), 1) AS cancel_pct
FROM orders GROUP BY is_b2b;
