-- 01_load.sql
-- Loads the cleaned orders and stock (from python/01_clean.py) into SQLite.
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
  order_id TEXT, order_date TEXT, month TEXT, in_trend INTEGER, status TEXT, outcome TEXT,
  fulfilment TEXT, service_level TEXT, sku TEXT, style TEXT, category TEXT, size TEXT,
  qty INTEGER, amount_inr REAL, amount_known INTEGER, net_revenue_inr REAL,
  state TEXT, city TEXT, is_b2b INTEGER, has_promotion INTEGER
);
DROP TABLE IF EXISTS stock;
CREATE TABLE stock (sku TEXT PRIMARY KEY, stock_units INTEGER, design TEXT, colour TEXT);
.mode csv
.import --skip 1 data/clean/orders_clean.csv orders
.import --skip 1 data/clean/stock_clean.csv stock
.mode list
CREATE INDEX ix_orders_sku ON orders(sku);
CREATE INDEX ix_orders_date ON orders(order_date);

-- Number of days of trading in each full month, for per-day comparisons
DROP VIEW IF EXISTS month_days;
CREATE VIEW month_days AS
SELECT month, count(DISTINCT order_date) AS days FROM orders WHERE in_trend = 1 GROUP BY month;
