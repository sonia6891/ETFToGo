"""Compact the app's bundled catalogue, annual fees and official ETF distributions for the web preview.

Run from the repository root:  python -I WebPreview/build_data.py

Distributions come from two official sources:
- TWSE "ETF 收益分配" (listed ETFs): ex-dividend, payment date and amount per unit, about two years back.
- TPEx 除權除息預告表 (OTC ETFs): upcoming ex-dividend dates and cash amounts only, so no payment date or history.
If a source cannot be reached, the previous snapshot of that source is kept.
"""
import json
import re
import urllib.request
from datetime import date, timedelta
from pathlib import Path

root = Path(__file__).resolve().parent.parent
target = Path(__file__).resolve().parent / "etf-data.json"
catalog = json.loads((root / "App/Resources/catalog.json").read_text(encoding="utf-8"))
fees = json.loads((root / "App/Resources/annual-fees.json").read_text(encoding="utf-8"))
previous = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {}

funds = [
    [f["id"], f["name"], f["strategy"], f.get("market") or "", f.get("fundType") or "", f.get("listingDate") or "", f.get("fullName") or ""]
    for f in catalog["funds"]
]
records = {
    code: [r["year"], r["total"], r["management"], r["custody"], r["commission"], r["tax"], r["subscriptionOffset"], r["guarantee"], r["other"], r["fundID"]]
    for code, r in sorted(fees["records"].items())
}
market = {f[0]: f[3] for f in funds}
listing = {f[0]: f[5] for f in funds}


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ETF ToGo data build)", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def roc(text):
    """'115年10月22日' or '1151016' -> '2026-10-22'; anything else -> ''."""
    m = re.fullmatch(r"(\d{2,3})年(\d{1,2})月(\d{1,2})日", (text or "").strip()) or re.fullmatch(r"(\d{3})(\d{2})(\d{2})", (text or "").strip())
    if not m:
        return ""
    y, mo, d = (int(x) for x in m.groups())
    return date(y + 1911, mo, d).isoformat()


def amount(text):
    try:
        value = float(str(text).replace(",", ""))
        return value if value > 0 else None
    except (TypeError, ValueError):
        return None


today = date.today()
old = previous.get("dividends") or {}
events = {}
sources = {}

try:
    start = (today - timedelta(days=760)).strftime("%Y%m%d")
    end = date(today.year + 1, 12, 31).strftime("%Y%m%d")
    twse = get_json(f"https://www.twse.com.tw/rwd/zh/ETF/etfDiv?stkNo=&startDate={start}&endDate={end}&response=json")
    if twse.get("status") != "ok" or twse.get("fields", [])[:3] != ["證券代號", "證券簡稱", "除息交易日"]:
        raise ValueError("unexpected TWSE response")
    for row in twse["data"]:
        sym, ex, pay = row[0].strip(), roc(row[2]), roc(row[4])
        if sym in market and ex:
            events.setdefault(sym, []).append([ex, pay, amount(row[5])])
    sources["twse"] = today.isoformat()
except Exception as error:  # keep the previous TWSE snapshot
    print("TWSE distributions not refreshed:", error)
    for sym, items in (old.get("events") or {}).items():
        if market.get(sym) == "TWSE":
            events[sym] = items
    if (old.get("sources") or {}).get("twse"):
        sources["twse"] = old["sources"]["twse"]

try:
    tpex = get_json("https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost")
    for row in tpex:
        sym, ex = str(row.get("SecuritiesCompanyCode", "")).strip(), roc(row.get("ExRrightsExDividendDate"))
        if market.get(sym) == "TPEx" and ex and "息" in str(row.get("ExRrightsExDividend", "")):
            events.setdefault(sym, []).append([ex, "", amount(row.get("CashDividend"))])
    sources["tpex"] = today.isoformat()
except Exception as error:  # keep the previous TPEx snapshot
    print("TPEx announcements not refreshed:", error)
    for sym, items in (old.get("events") or {}).items():
        if market.get(sym) == "TPEx":
            events[sym] = items
    if (old.get("sources") or {}).get("tpex"):
        sources["tpex"] = old["sources"]["tpex"]

for sym in events:
    unique = {item[0]: item for item in events[sym]}
    events[sym] = sorted(unique.values(), key=lambda item: item[0], reverse=True)


def frequency(sym):
    """Distribution frequency from the number of ex-dividend dates in the past year (listed ETFs only)."""
    if market.get(sym) != "TWSE" or "twse" not in sources:
        return None
    year_ago = (today - timedelta(days=365)).isoformat()
    n = sum(1 for ex, _, _ in events.get(sym, []) if year_ago < ex <= today.isoformat())
    if n >= 9:
        return "月配"
    if n >= 5:
        return "雙月配"
    if n >= 3:
        return "季配"
    if n == 2:
        return "半年配"
    if n == 1:
        return "年配"
    listed = listing.get(sym) or ""
    if not events.get(sym) and listed and listed <= (today - timedelta(days=730)).isoformat():
        return "不配息"
    return None


freq = {sym: label for sym in market if (label := frequency(sym))}
out = {
    "catalog": {"listedDate": catalog["listedDate"], "fetchedDay": catalog["fetchedDay"], "funds": funds},
    "fees": {"fetchedDay": fees["fetchedDay"], "sourceURL": fees["sourceURL"], "records": records},
    "dividends": {"sources": sources, "events": events, "freq": freq},
}
target.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(funds)} funds, {len(records)} fee records, {sum(len(v) for v in events.values())} distributions for {len(events)} ETFs, "
      f"{len(freq)} frequencies -> {target.name} ({target.stat().st_size // 1024} KB)")
