"""Cleans the Amazon.in order report and stock report for one Indian apparel seller (Apr-Jun 2022).

Reads  data/raw/amazon_sale_report.csv.gz   original Kaggle export, 128,975 order lines
       data/raw/stock_report.csv            stock on hand per SKU (one snapshot, date not given)
       archive_2024/2024_cleaned_data.csv.gz  the 2024 version, only to measure what it dropped
Writes data/clean/orders_clean.csv       one row per order line, analysis-ready
       data/clean/stock_clean.csv        one row per SKU
       data/clean/data_quality_log.csv   every issue found and what was done about it

Run from the project root:  .venv/bin/python python/01_clean.py
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "clean"
OUT.mkdir(parents=True, exist_ok=True)

# Every spelling in the file that does not already match an official state/territory name
STATE_ALIASES = {
    "AR": "ARUNACHAL PRADESH", "NL": "NAGALAND", "PB": "PUNJAB", "RJ": "RAJASTHAN",
    "RAJSHTHAN": "RAJASTHAN", "RAJSTHAN": "RAJASTHAN", "ORISSA": "ODISHA",
    "NEW DELHI": "DELHI", "PONDICHERRY": "PUDUCHERRY", "PUNJAB/MOHALI/ZIRAKPUR": "PUNJAB",
    "ANDAMAN & NICOBAR": "ANDAMAN AND NICOBAR ISLANDS", "DADRA AND NAGAR": "DADRA AND NAGAR HAVELI",
    "JAMMU & KASHMIR": "JAMMU AND KASHMIR", "APO": None,
}

# Amazon's 13 statuses collapsed into what happened to the order
OUTCOME = {
    "Cancelled": "Cancelled",
    "Shipped": "Shipped",
    "Shipped - Delivered to Buyer": "Shipped",
    "Shipped - Picked Up": "Shipped",
    "Shipped - Out for Delivery": "Shipped",
    "Shipped - Returned to Seller": "Returned",
    "Shipped - Returning to Seller": "Returned",
    "Shipped - Rejected by Buyer": "Returned",
    "Shipped - Lost in Transit": "Lost or damaged",
    "Shipped - Damaged": "Lost or damaged",
    "Pending": "Pending",
    "Pending - Waiting for Pick Up": "Pending",
    "Shipping": "Pending",
}

log = []


def note(issue, rows, action):
    log.append({"issue": issue, "rows_affected": int(rows), "action": action})


# =============================== ORDERS ===============================
df = pd.read_csv(RAW / "amazon_sale_report.csv.gz", low_memory=False)
df.columns = [c.strip() for c in df.columns]
n_raw = len(df)

# What the 2024 cleaning threw away
old = pd.read_csv(ROOT / "archive_2024" / "2024_cleaned_data.csv.gz", usecols=["Status"])
note("Rows deleted by the 2024 cleaning (no amount)", n_raw - len(old),
     f"Restored. {(df.Status == 'Cancelled').sum() - (old.Status == 'Cancelled').sum():,} of them are cancelled orders, "
     "so the 2024 cancellation rate was understated")

# --- Dates and amounts ---
df["order_date"] = pd.to_datetime(df["Date"], format="%m-%d-%y", errors="coerce")
assert df.order_date.notna().all(), "Unparsed dates"
df["amount_inr"] = pd.to_numeric(df["Amount"], errors="coerce")
no_amount = df.amount_inr.isna()
note("Amount missing", no_amount.sum(),
     f"Kept as real orders ({(no_amount & (df.Status == 'Cancelled')).sum():,} are cancelled); "
     "flagged amount_known = 0 and counted as 0 in revenue totals")
df["amount_known"] = (~no_amount).astype(int)
df["amount_inr"] = df.amount_inr.fillna(0)

# --- Duplicates ---
dupes = df.duplicated(["Order ID", "SKU", "Qty", "Amount", "Status", "Date"])
note("Exact duplicate order lines", dupes.sum(), "Removed")
df = df[~dupes].copy()

# --- Order outcome ---
unknown = ~df["Status"].isin(OUTCOME)
assert not unknown.any(), f"Unmapped status: {df.loc[unknown, 'Status'].unique()}"
df["outcome"] = df["Status"].map(OUTCOME)
note("13 raw statuses", len(df), "Grouped into 5 outcomes: Shipped, Cancelled, Returned, Pending, Lost or damaged")
note("Cancelled orders that carry an amount", ((df.outcome == "Cancelled") & (df.amount_inr > 0)).sum(),
     "Excluded from net revenue (net revenue = Shipped only)")
note("Shipped with amount 0 (likely free replacements)", ((df.outcome == "Shipped") & (df.amount_inr == 0)).sum(),
     "Kept; they count as units but add no revenue")

# --- Promotions: a recording artifact, not a driver ---
df["has_promotion"] = df["promotion-ids"].notna().astype(int)
cancelled_with_promo = ((df.outcome == "Cancelled") & (df.has_promotion == 1)).sum()
note("Promotion codes are only recorded on orders that shipped", (df.has_promotion == 0).sum(),
     f"Only {cancelled_with_promo} of {(df.outcome == 'Cancelled').sum():,} cancelled orders carry a code, so "
     "'promotions prevent cancellations' would be a false reading. Field kept but not used to explain cancellations")

# --- States and cities ---
state = df["ship-state"].astype("string").str.upper().str.strip()
raw_spellings = df["ship-state"].nunique()
state = state.map(lambda s: STATE_ALIASES.get(s, s) if pd.notna(s) else s)
df["state"] = state.str.title().str.replace(" And ", " and ")
note("State spelled inconsistently", raw_spellings - df.state.nunique(),
     f"{raw_spellings} spellings merged into {df.state.nunique()} states and territories")
note("Ship state missing", df.state.isna().sum(), "Labelled 'Unknown'")
df["state"] = df.state.fillna("Unknown")
df["city"] = df["ship-city"].astype("string").str.upper().str.strip().str.title().fillna("Unknown")

# --- Tidy fields ---
df["sku"] = df["SKU"].str.upper().str.strip()
df["category"] = df["Category"].str.strip().str.title()
df["fulfilment"] = df["Fulfilment"].map({"Amazon": "Fulfilled by Amazon", "Merchant": "Shipped by seller"})
# 31 Mar is a partial day; on 27-29 Jun many orders had not shipped yet (32% still pending on 28 Jun),
# which would understate recent net revenue
partial = (df.order_date < "2022-04-01") | (df.order_date > "2022-06-26")
note("Days unsuitable for trends: 31 Mar (partial) and 27-29 Jun (orders not yet shipped)", partial.sum(),
     "Kept in totals, flagged in_trend = 0; per-day trends use 1 Apr to 26 Jun")
note("Returns are only recorded for seller-shipped orders",
     ((df.outcome == "Returned") & (df.Fulfilment == "Amazon")).sum(),
     "Amazon-fulfilled returns are handled by Amazon and absent from this report; return rates are shown for seller-shipped orders only")

orders = pd.DataFrame({
    "order_id": df["Order ID"],
    "order_date": df.order_date.dt.date,
    "month": df.order_date.dt.strftime("%Y-%m"),
    "in_trend": (~partial).astype(int),
    "status": df["Status"],
    "outcome": df.outcome,
    "fulfilment": df.fulfilment,
    "service_level": df["ship-service-level"],
    "sku": df.sku,
    "style": df["Style"].str.upper().str.strip(),
    "category": df.category,
    "size": df["Size"],
    "qty": df["Qty"],
    "amount_inr": df.amount_inr,
    "amount_known": df.amount_known,
    "net_revenue_inr": df.amount_inr.where(df.outcome == "Shipped", 0),
    "state": df.state,
    "city": df.city,
    "is_b2b": df["B2B"].astype(bool).astype(int),
    "has_promotion": df.has_promotion,
})
orders.to_csv(OUT / "orders_clean.csv", index=False)

# =============================== STOCK ===============================
st = pd.read_csv(RAW / "stock_report.csv")
st["sku"] = st["SKU Code"].astype("string").str.upper().str.strip()
no_stock = st.Stock.isna() | st.sku.isna()
note("Stock report: SKU or stock quantity missing", no_stock.sum(), "Removed")
st = st[~no_stock]
dup_sku = st.sku.duplicated(keep=False)
note("Stock report: SKU listed more than once", dup_sku.sum(), "Stock quantities summed per SKU")
stock = (st.groupby("sku", as_index=False)
           .agg(stock_units=("Stock", "sum"), design=("Design No.", "first"), colour=("Color", "first")))
stock["stock_units"] = stock.stock_units.astype(int)
stock.to_csv(OUT / "stock_clean.csv", index=False)

sold = set(orders.sku)
matched = orders.sku.isin(set(stock.sku))
note("Order lines whose SKU has no stock record", (~matched).sum(),
     f"{matched.mean():.1%} of order lines match the stock report; unmatched SKUs are excluded from stock-cover analysis only")
note("Stock snapshot has no date", len(stock),
     "Treated as stock on hand at the end of the sales period; stock-cover figures are indicative")
note("Kaggle price lists (May-2022, P&L March 2021) share no SKUs with the Amazon orders", 0,
     "Not used: they describe a different product range, so profit margins cannot be computed")

pd.DataFrame(log).to_csv(OUT / "data_quality_log.csv", index=False)
print(f"{n_raw:,} raw order lines -> {len(orders):,} clean | {len(stock):,} SKUs in stock report")
print(pd.DataFrame(log).to_string(index=False, justify="left", max_colwidth=70))
