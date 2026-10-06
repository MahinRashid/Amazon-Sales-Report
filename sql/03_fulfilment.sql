-- 03_fulfilment.sql
-- Should the seller ship orders itself or let Amazon do it?
.headers on
.mode column

SELECT fulfilment, count(*) AS order_lines,
       round(100.0 * count(*) / (SELECT count(*) FROM orders), 1) AS pct_of_lines,
       round(100.0 * sum(outcome = 'Cancelled') / count(*), 1) AS cancel_pct,
       round(100.0 * sum(outcome = 'Returned') / sum(outcome IN ('Shipped', 'Returned')), 1) AS return_pct_of_shipped,
       round(sum(net_revenue_inr) / 1e6, 2) AS net_inr_m,
       round(sum(net_revenue_inr) / sum(outcome = 'Shipped'), 0) AS net_per_shipped_line
FROM orders GROUP BY fulfilment;

-- Share of ordered lines that end as kept revenue (not cancelled, not returned)
SELECT fulfilment,
       round(100.0 * sum(outcome = 'Shipped') / count(*), 1) AS kept_pct,
       round(100.0 * sum(outcome IN ('Cancelled', 'Returned')) / count(*), 1) AS lost_pct
FROM orders GROUP BY fulfilment;

-- Does the gap hold within each category? (rules out a product-mix explanation)
SELECT category,
       round(100.0 * sum(CASE WHEN fulfilment = 'Fulfilled by Amazon' AND outcome = 'Cancelled' THEN 1 ELSE 0 END) / sum(fulfilment = 'Fulfilled by Amazon'), 1) AS amazon_cancel_pct,
       round(100.0 * sum(CASE WHEN fulfilment = 'Shipped by seller' AND outcome = 'Cancelled' THEN 1 ELSE 0 END) / sum(fulfilment = 'Shipped by seller'), 1) AS seller_cancel_pct,
       count(*) AS order_lines
FROM orders GROUP BY category HAVING count(*) >= 1000 ORDER BY order_lines DESC;

-- Fulfilment mix and cancellation by month
SELECT month,
       round(100.0 * sum(fulfilment = 'Shipped by seller') / count(*), 1) AS seller_share_pct,
       round(100.0 * sum(outcome = 'Cancelled') / count(*), 1) AS cancel_pct
FROM orders WHERE in_trend = 1 GROUP BY month;

-- Scenario: seller-shipped orders cancel and return at Amazon's cancel rate (returns unchanged)
WITH r AS (
  SELECT sum(CASE WHEN fulfilment = 'Fulfilled by Amazon' AND outcome = 'Cancelled' THEN 1.0 ELSE 0 END) / sum(fulfilment = 'Fulfilled by Amazon') AS amazon_rate,
         sum(CASE WHEN fulfilment = 'Shipped by seller' AND outcome = 'Cancelled' THEN 1.0 ELSE 0 END) / sum(fulfilment = 'Shipped by seller') AS seller_rate,
         sum(fulfilment = 'Shipped by seller') AS seller_lines,
         sum(CASE WHEN fulfilment = 'Shipped by seller' THEN net_revenue_inr END) / sum(fulfilment = 'Shipped by seller' AND outcome = 'Shipped') AS seller_value
  FROM orders
)
SELECT round(100 * seller_rate, 1) AS seller_cancel_pct, round(100 * amazon_rate, 1) AS amazon_cancel_pct,
       round((seller_rate - amazon_rate) * seller_lines, 0) AS orders_saved,
       round((seller_rate - amazon_rate) * seller_lines * seller_value / 1e6, 2) AS revenue_saved_inr_m_3_months
FROM r;

-- Service level
SELECT service_level, fulfilment, count(*) AS order_lines,
       round(100.0 * sum(outcome = 'Cancelled') / count(*), 1) AS cancel_pct
FROM orders GROUP BY service_level, fulfilment ORDER BY order_lines DESC;
