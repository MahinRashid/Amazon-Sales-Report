-- 02_revenue_and_outcomes.sql
-- How much of what was ordered actually became revenue, and how is revenue trending?
.headers on
.mode column

-- What happened to every order line
SELECT outcome, count(*) AS order_lines,
       round(100.0 * count(*) / (SELECT count(*) FROM orders), 1) AS pct_of_lines,
       round(sum(amount_inr) / 1e6, 2) AS value_inr_m,
       sum(amount_known = 0) AS lines_with_no_amount
FROM orders GROUP BY outcome ORDER BY order_lines DESC;

-- Gross (everything with an amount) vs net (shipped only)
SELECT round(sum(amount_inr) / 1e6, 2) AS gross_inr_m,
       round(sum(net_revenue_inr) / 1e6, 2) AS net_inr_m,
       round(100.0 * (sum(amount_inr) - sum(net_revenue_inr)) / sum(amount_inr), 1) AS pct_overstated
FROM orders;

-- Value lost to cancellations: recorded amounts plus an estimate for lines with no amount,
-- priced at the average shipped line value of the same category
WITH avg_price AS (
  SELECT category, avg(amount_inr) AS price FROM orders WHERE outcome = 'Shipped' AND amount_inr > 0 GROUP BY category
)
SELECT round(sum(CASE WHEN o.amount_known = 1 THEN o.amount_inr END) / 1e6, 2) AS recorded_inr_m,
       round(sum(CASE WHEN o.amount_known = 0 THEN a.price END) / 1e6, 2) AS estimated_inr_m,
       round((sum(CASE WHEN o.amount_known = 1 THEN o.amount_inr END) + sum(CASE WHEN o.amount_known = 0 THEN a.price END)) / 1e6, 2) AS total_inr_m
FROM orders o JOIN avg_price a USING (category) WHERE o.outcome = 'Cancelled';

-- Monthly trend, per trading day (months have different lengths)
SELECT o.month, d.days,
       round(sum(o.net_revenue_inr) / 1e6, 2) AS net_inr_m,
       round(sum(o.net_revenue_inr) / d.days / 1e3, 0) AS net_per_day_k,
       round(1.0 * sum(CASE WHEN o.outcome = 'Shipped' THEN o.qty END) / d.days, 0) AS units_per_day,
       round(sum(o.net_revenue_inr) / sum(CASE WHEN o.outcome = 'Shipped' THEN o.qty END), 0) AS revenue_per_unit
FROM orders o JOIN month_days d USING (month) WHERE o.in_trend = 1 GROUP BY o.month;

-- Which categories drove the change from April to June (net revenue per day)
WITH per_day AS (
  SELECT o.category, o.month, sum(o.net_revenue_inr) / d.days AS rev
  FROM orders o JOIN month_days d USING (month) WHERE o.in_trend = 1 GROUP BY o.category, o.month
)
SELECT category,
       round(max(CASE WHEN month = '2022-04' THEN rev END) / 1e3, 0) AS apr_per_day_k,
       round(max(CASE WHEN month = '2022-06' THEN rev END) / 1e3, 0) AS jun_per_day_k,
       round((max(CASE WHEN month = '2022-06' THEN rev END) - max(CASE WHEN month = '2022-04' THEN rev END)) / 1e3, 0) AS change_k,
       round(100.0 * (max(CASE WHEN month = '2022-06' THEN rev END) / max(CASE WHEN month = '2022-04' THEN rev END) - 1), 0) AS change_pct
FROM per_day GROUP BY category ORDER BY apr_per_day_k DESC;
