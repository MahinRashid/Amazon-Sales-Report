-- 05_stock_cover.sql
-- Is the seller holding the right stock? Joins shipped demand to the stock report by SKU.
-- Weeks of cover = stock on hand / average units shipped per week over the 13-week period.
-- The stock snapshot is undated, so treat cover as indicative.
.headers on
.mode column

DROP TABLE IF EXISTS sku_cover;
CREATE TABLE sku_cover AS
WITH demand AS (
  SELECT sku, max(style) AS style, max(category) AS category, max(size) AS size,
         sum(qty) AS units, sum(net_revenue_inr) AS rev
  FROM orders WHERE outcome = 'Shipped' GROUP BY sku
),
ranked AS (SELECT *, ntile(10) OVER (ORDER BY rev DESC) AS rev_decile FROM demand)
SELECT r.sku, r.style, r.category, r.size, r.units, r.rev, r.rev_decile,
       s.stock_units,
       round(r.units / 13.0, 2) AS units_per_week,
       CASE WHEN s.stock_units IS NULL OR r.units = 0 THEN NULL ELSE round(s.stock_units / (r.units / 13.0), 1) END AS weeks_of_cover,
       CASE WHEN s.stock_units IS NULL THEN 'No stock record'
            WHEN r.units = 0 THEN 'No paid units'
            WHEN s.stock_units = 0 THEN '1. Out of stock'
            WHEN s.stock_units / (r.units / 13.0) < 2 THEN '2. Under 2 weeks'
            WHEN s.stock_units / (r.units / 13.0) < 4 THEN '3. 2-4 weeks'
            WHEN s.stock_units / (r.units / 13.0) < 13 THEN '4. 4-13 weeks'
            ELSE '5. Over 13 weeks' END AS cover_band
FROM ranked r LEFT JOIN stock s USING (sku);

-- Revenue by stock cover: how much of the business sits on thin stock?
SELECT cover_band, count(*) AS skus, round(sum(rev) / 1e6, 2) AS net_inr_m,
       round(100.0 * sum(rev) / (SELECT sum(rev) FROM sku_cover), 1) AS pct_of_revenue
FROM sku_cover GROUP BY cover_band ORDER BY cover_band;

-- Best-sellers (top 10% of SKUs by revenue) at risk
SELECT count(*) AS best_seller_skus,
       round(100.0 * sum(rev) / (SELECT sum(rev) FROM sku_cover), 1) AS pct_of_revenue,
       sum(cover_band = '1. Out of stock') AS out_of_stock,
       sum(cover_band = '2. Under 2 weeks') AS under_2_weeks,
       sum(cover_band = '3. 2-4 weeks') AS two_to_4_weeks,
       round(sum(CASE WHEN cover_band IN ('1. Out of stock', '2. Under 2 weeks') THEN rev END) / 1e6, 2) AS revenue_at_risk_inr_m
FROM sku_cover WHERE rev_decile = 1;

-- The ten best-sellers with the least cover
SELECT sku, category, units, round(rev / 1e3, 0) AS net_inr_k, stock_units, weeks_of_cover
FROM sku_cover WHERE rev_decile = 1 AND stock_units IS NOT NULL
ORDER BY weeks_of_cover, rev DESC LIMIT 10;

-- Stock that is not selling on Amazon: in the stock report but zero shipped units in 13 weeks
SELECT count(*) AS skus_not_selling, sum(s.stock_units) AS units_held,
       round(100.0 * sum(s.stock_units) / (SELECT sum(stock_units) FROM stock), 1) AS pct_of_all_stock
FROM stock s LEFT JOIN sku_cover c USING (sku)
WHERE c.sku IS NULL AND s.stock_units > 0;

-- Slow stock: sold, but more than a year of cover
SELECT count(*) AS skus, sum(stock_units) AS units_held,
       round(100.0 * sum(stock_units) / (SELECT sum(stock_units) FROM stock), 1) AS pct_of_all_stock
FROM sku_cover WHERE weeks_of_cover > 52;

-- Did thin stock make the April-to-June fall worse? Change in units shipped per day, by stock cover
WITH m AS (
  SELECT sku, category,
         sum(CASE WHEN month = '2022-04' AND outcome = 'Shipped' AND in_trend = 1 THEN qty ELSE 0 END) / 30.0 AS apr,
         sum(CASE WHEN month = '2022-06' AND outcome = 'Shipped' AND in_trend = 1 THEN qty ELSE 0 END) / 26.0 AS jun
  FROM orders GROUP BY sku
)
SELECT CASE WHEN c.cover_band IN ('1. Out of stock', '2. Under 2 weeks') THEN 'Thin (under 2 weeks)'
            WHEN c.cover_band = 'No stock record' THEN 'No stock record'
            ELSE 'Adequate (2+ weeks)' END AS stock_cover,
       round(100.0 * (sum(CASE WHEN m.category = 'Set' THEN m.jun END) / sum(CASE WHEN m.category = 'Set' THEN m.apr END) - 1), 0) AS sets_change_pct,
       round(100.0 * (sum(m.jun) / sum(m.apr) - 1), 0) AS all_products_change_pct
FROM m JOIN sku_cover c USING (sku) GROUP BY 1;
