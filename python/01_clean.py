"""Cleans the Amazon.in order report for one Indian apparel seller (Apr-Jun 2022).

Reads  data/raw/Amazon Sale Report.csv         the original Kaggle export, if present
       data/raw/amazon_sales_2024_cleaned.csv  otherwise: the 2024 version, which had already
                                               dropped rows with no amount (mostly cancellations)
Writes data/clean/orders_clean.csv       one row per order line, analysis-ready
       data/clean/data_quality_log.csv   every issue found and what was done about it

Run from the project root:  .venv/bin/python python/01_clean.py
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW_ORIGINAL = ROOT / "data" / "raw" / "Amazon Sale Report.csv"
RAW_2024 = ROOT / "data" / "raw" / "amazon_sales_2024_cleaned.csv"
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

# Amazon's 12 statuses collapsed into what happened to the order
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


source = RAW_ORIGINAL if RAW_ORIGINAL.exists() else RAW_2024
df = pd.read_csv(source, low_memory=False)
df.columns = [c.strip() for c in df.columns]
print(f"Source: {source.name} ({len(df):,} rows)")
if source == RAW_2024:
    note("2024 version deleted rows with no amount (mostly cancelled orders)", 0,
         "Cannot be restored from this file: add the original 'Amazon Sale Report.csv' to data/raw/")

# --- Dates and amounts -----------------------------------------------------------
df["order_date"] = pd.to_datetime(df["Date"], errors="coerce", format="mixed")
df["amount_inr"] = pd.to_numeric(df["Amount"], errors="coerce")
no_amount = df.amount_inr.isna()
note("Amount missing", no_amount.sum(),
     "Kept the row (it is a real order, usually cancelled) with amount treated as 0 in revenue totals")
df["amount_inr"] = df.amount_inr.fillna(0)

# --- Duplicates --------------------------------------------------------------------
dupes = df.duplicated(["Order ID", "SKU", "Qty", "Amount", "Status"])
note("Exact duplicate order lines", dupes.sum(), "Removed")
df = df[~dupes].copy()

# --- Order outcome -----------------------------------------------------------------
unknown = ~df["Status"].isin(OUTCOME)
assert not unknown.any(), f"Unmapped status: {df.loc[unknown, 'Status'].unique()}"
df["outcome"] = df["Status"].map(OUTCOME)
note("12 raw statuses", len(df), "Grouped into 5 outcomes: Shipped, Cancelled, Returned, Pending, Lost or damaged")
note("Cancelled orders carry an amount", ((df.outcome == "Cancelled") & (df.amount_inr > 0)).sum(),
     "Excluded from net revenue (net revenue = Shipped only)")
note("Shipped with amount 0 (likely free replacements)", ((df.outcome == "Shipped") & (df.amount_inr == 0)).sum(),
     "Kept; they count as units but add no revenue")

# --- States and cities ---------------------------------------------------------------
state = df["ship-state"].astype("string").str.upper().str.strip()
raw_spellings = df["ship-state"].nunique()
state = state.map(lambda s: STATE_ALIASES.get(s, s) if pd.notna(s) else s)
df["state"] = state.str.title().str.replace(" And ", " and ")
note("State spelled inconsistently", raw_spellings - df.state.nunique(),
     f"{raw_spellings} spellings merged into {df.state.nunique()} states and territories")
note("Ship state missing", df.state.isna().sum(), "Labelled 'Unknown'")
df["state"] = df.state.fillna("Unknown")
df["city"] = df["ship-city"].astype("string").str.upper().str.strip().str.title().fillna("Unknown")

# --- Tidy fields ---------------------------------------------------------------------
df["category"] = df["Category"].str.strip().str.title()
df["fulfilment"] = df["Fulfilment"].map({"Amazon": "Fulfilled by Amazon", "Merchant": "Shipped by seller"})
df["is_b2b"] = df["B2B"].astype(bool).astype(int)
has_promo = "promotion-ids" in df.columns
if has_promo:
    df["has_promotion"] = df["promotion-ids"].notna().astype(int)
else:
    note("Promotion column was deleted in the 2024 version", 0, "Promotion analysis needs the original file")

partial = df.order_date < "2022-04-01"
note("Orders dated before April (a single partial day)", partial.sum(), "Kept, flagged is_full_month = 0; monthly trends use Apr-Jun")

clean = pd.DataFrame({
    "order_id": df["Order ID"],
    "order_date": df.order_date.dt.date,
    "month": df.order_date.dt.strftime("%Y-%m"),
    "is_full_month": (~partial).astype(int),
    "status": df["Status"],
    "outcome": df.outcome,
    "fulfilment": df.fulfilment,
    "service_level": df["ship-service-level"],
    "sku": df["SKU"],
    "style": df["Style"],
    "category": df.category,
    "size": df["Size"],
    "qty": df["Qty"],
    "amount_inr": df.amount_inr,
    "net_revenue_inr": df.amount_inr.where(df.outcome == "Shipped", 0),
    "state": df.state,
    "city": df.city,
    "is_b2b": df.is_b2b,
    **({"has_promotion": df.has_promotion} if has_promo else {}),
})
clean.to_csv(OUT / "orders_clean.csv", index=False)
pd.DataFrame(log).to_csv(OUT / "data_quality_log.csv", index=False)

print(f"{len(clean):,} order lines cleaned -> {OUT / 'orders_clean.csv'}")
print(pd.DataFrame(log).to_string(index=False, justify="left", max_colwidth=80))
