"""Compact the app's bundled catalogue and annual-fee data for the web preview.

Run from the repository root:  python -I WebPreview/build_data.py
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "App/Resources/catalog.json").read_text(encoding="utf-8"))
fees = json.loads((root / "App/Resources/annual-fees.json").read_text(encoding="utf-8"))

funds = [
    [f["id"], f["name"], f["strategy"], f.get("market") or "", f.get("fundType") or "", f.get("listingDate") or "", f.get("fullName") or ""]
    for f in catalog["funds"]
]
records = {
    code: [r["year"], r["total"], r["management"], r["custody"], r["commission"], r["tax"], r["subscriptionOffset"], r["guarantee"], r["other"], r["fundID"]]
    for code, r in sorted(fees["records"].items())
}
out = {
    "catalog": {"listedDate": catalog["listedDate"], "fetchedDay": catalog["fetchedDay"], "funds": funds},
    "fees": {"fetchedDay": fees["fetchedDay"], "sourceURL": fees["sourceURL"], "records": records},
}
target = Path(__file__).resolve().parent / "etf-data.json"
target.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(funds)} funds, {len(records)} fee records -> {target.name} ({target.stat().st_size // 1024} KB)")
