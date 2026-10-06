-- 07_powerbi_exports.sql
-- Writes a star schema for Power BI into powerbi/data/.
-- Requires 05_stock_cover.sql to have run first (uses the sku_cover table).
--
--   dim_product (1) ──< fact_orders >── (1) dim_state        dim_date is created in Power BI with DAX
.headers on
.mode csv

-- One row per order line
.output powerbi/data/fact_orders.csv
SELECT order_id, order_date, in_trend, outcome, status, fulfilment, service_level,
       sku, state, qty, amount_inr, net_revenue_inr, amount_known, is_b2b,
       CASE WHEN outcome = 'Cancelled' THEN 1 ELSE 0 END AS is_cancelled,
       CASE WHEN outcome = 'Returned' THEN 1 ELSE 0 END AS is_returned,
       CASE WHEN outcome = 'Shipped' THEN 1 ELSE 0 END AS is_shipped
FROM orders;

-- One row per SKU ever ordered, with stock and cover
.output powerbi/data/dim_product.csv
WITH p AS (
  SELECT sku, max(style) AS style, max(category) AS category, max(size) AS size FROM orders GROUP BY sku
)
SELECT p.sku, p.style, p.category, p.size,
       s.stock_units,
       c.units AS units_shipped_13w, c.units_per_week, c.weeks_of_cover,
       COALESCE(c.cover_band, CASE WHEN s.stock_units IS NULL THEN 'No stock record' ELSE 'No paid units' END) AS cover_band,
       CASE WHEN c.rev_decile = 1 THEN 'Best-seller (top 10%)' ELSE 'Other' END AS product_tier
FROM p LEFT JOIN stock s USING (sku) LEFT JOIN sku_cover c USING (sku);

-- One row per state
.output powerbi/data/dim_state.csv
SELECT state, count(*) AS order_lines FROM orders GROUP BY state;

-- Stock that is not selling on Amazon (in the stock report, nothing shipped in 13 weeks)
.output powerbi/data/stock_not_selling.csv
SELECT s.sku, s.design, s.colour, s.stock_units
FROM stock s LEFT JOIN sku_cover c USING (sku)
WHERE c.sku IS NULL AND s.stock_units > 0;
.output stdout
