#!/bin/sh
# Rebuilds everything from the raw files: clean data, SQL results, Power BI tables, charts.
set -e
cd "$(dirname "$0")"
PY=.venv/bin/python
$PY python/01_clean.py > outputs/01_clean_log.txt
rm -f amazon.db
sqlite3 amazon.db < sql/01_load.sql
for f in 02_revenue_and_outcomes 03_fulfilment 04_products 05_stock_cover 06_geography; do
  echo "Running $f..."
  sqlite3 amazon.db < "sql/$f.sql" > "outputs/$f.txt"
done
mkdir -p powerbi/data
sqlite3 amazon.db < sql/07_powerbi_exports.sql
$PY python/build_notebook.py > /dev/null
(cd notebooks && ../$PY -m nbconvert --to notebook --execute --inplace analysis.ipynb 2> /dev/null)
echo "Done. Results in outputs/, charts in outputs/charts/, Power BI tables in powerbi/data/."
