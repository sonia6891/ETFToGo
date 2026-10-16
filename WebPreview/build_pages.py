"""Build the standalone web app (GitHub Pages) from WebPreview/index.html.

The Claude artifact version is published from index.html as-is; this wraps the same
page in a full document with the app icon and home-screen metadata.

Usage, from the repository root:  python -I WebPreview/build_pages.py <output-dir>
"""
import hashlib
import io
import json
import plistlib
import shutil
import sys
import uuid
from pathlib import Path

from PIL import Image

here = Path(__file__).resolve().parent
root = here.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)

# The home-screen icon is the iPhone app icon (blue, full bleed; iOS rounds the corners).
app_icon = root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# iOS keeps a home-screen icon per URL, so icon and manifest names carry the icon's content hash:
# a new icon gets new URLs and is fetched again when the page is re-added to the home screen.
# Bump ICON_REVISION to force new icon URLs when the image is unchanged but iOS kept a bad copy.
ICON_REVISION = b"2"
version = hashlib.sha256(app_icon.read_bytes() + ICON_REVISION).hexdigest()[:8]
icons = {size: f"icon-{version}-{size}.png" for size in (180, 192, 512)}
# Absolute URLs: the home-screen sheet resolves icons outside the page, so nothing depends on the base URL.
site = "https://sonia6891.github.io/etftogo-web/"
manifest_name = f"manifest-{version}.webmanifest"
for stale in [*out.glob("icon-*.png"), *out.glob("manifest*.webmanifest")]:
    stale.unlink()

page = (here / "index.html").read_text(encoding="utf-8")
# index.html starts with its own charset/viewport lines for local testing; the wrapper supplies them.
lines = [line for line in page.splitlines() if not line.startswith("<meta charset") and not line.startswith('<meta name="viewport"')]
title = next(line for line in lines if line.startswith("<title>"))
lines.remove(title)
head = "\n".join([
    "<!doctype html>",
    '<html lang="zh-Hant">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">',
    title,
    '<meta name="apple-mobile-web-app-capable" content="yes">',
    '<meta name="mobile-web-app-capable" content="yes">',
    '<meta name="apple-mobile-web-app-title" content="投資袋著走">',
    '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
    '<meta name="theme-color" content="#edf2ff" media="(prefers-color-scheme: light)">',
    '<meta name="theme-color" content="#0e1628" media="(prefers-color-scheme: dark)">',
    '<meta name="description" content="投資袋著走：台灣上市 ETF 持有、配息與試算的網頁版。">',
    f'<link rel="apple-touch-icon" sizes="180x180" href="{site}{icons[180]}">',
    f'<link rel="apple-touch-icon-precomposed" sizes="180x180" href="{site}{icons[180]}">',
    f'<link rel="icon" type="image/png" sizes="192x192" href="{site}{icons[192]}">',
    f'<link rel="manifest" href="{site}{manifest_name}">',
    "<style>html,body{margin:0;height:100%}</style>",
    "</head>",
    "<body>",
])
(out / "index.html").write_text(head + "\n" + "\n".join(lines) + "\n</body>\n</html>\n", encoding="utf-8")

icon = Image.open(app_icon).convert("RGB")
for size, name in icons.items():
    icon.resize((size, size), Image.LANCZOS).save(out / name, optimize=True)
# Fallbacks for clients that probe the conventional names instead of reading the links.
for name in ("apple-touch-icon.png", "apple-touch-icon-precomposed.png", "apple-touch-icon-180x180.png"):
    icon.resize((180, 180), Image.LANCZOS).save(out / name, optimize=True)
icon.save(out / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

manifest = {
    "id": "./",
    "name": "投資袋著走",
    "short_name": "投資袋著走",
    "lang": "zh-Hant",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "background_color": "#edf2ff",
    "theme_color": "#edf2ff",
    "icons": [
        {"src": site + icons[180], "sizes": "180x180", "type": "image/png", "purpose": "any"},
        {"src": site + icons[192], "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": site + icons[512], "sizes": "512x512", "type": "image/png", "purpose": "any"},
    ],
}
(out / manifest_name).write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

# A Web Clip configuration profile puts the app on the home screen with this exact icon, without relying on
# Safari to fetch it. It holds only the web clip; the viewer installs it in Settings and can remove it there.
clip_png = io.BytesIO()
icon.resize((400, 400), Image.LANCZOS).save(clip_png, format="PNG", optimize=True)
clip = {
    "PayloadType": "com.apple.webClip.managed", "PayloadVersion": 1,
    "PayloadIdentifier": "io.github.sonia6891.etftogo.webclip",
    "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_URL, site + "#webclip")).upper(),
    "PayloadDisplayName": "投資袋著走 主畫面圖示",
    "Label": "投資袋著走", "URL": site, "Icon": clip_png.getvalue(),
    "FullScreen": True, "IsRemovable": True, "Precomposed": True,
}
profile = {
    "PayloadType": "Configuration", "PayloadVersion": 1,
    "PayloadIdentifier": "io.github.sonia6891.etftogo",
    "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_URL, site + "#profile")).upper(),
    "PayloadDisplayName": "投資袋著走",
    "PayloadDescription": "在主畫面加入 投資袋著走網頁 App（藍底口袋圖示）。只包含一個主畫面圖示，不會變更其他設定。",
    "PayloadRemovalDisallowed": False,
    "PayloadContent": [clip],
}
(out / "ETFToGo.mobileconfig").write_bytes(plistlib.dumps(profile))
shutil.copyfile(here / "etf-data.json", out / "etf-data.json")
shutil.copyfile(here / "stock-data.json", out / "stock-data.json")
# Illustrations (made with Figma AI, prepared by prepare_art.py) are referenced as assets/<name>.png.
shutil.copytree(here / "assets", out / "assets", dirs_exist_ok=True)
(out / ".nojekyll").write_text("", encoding="utf-8")
print("built", sorted(p.name for p in out.iterdir()))
