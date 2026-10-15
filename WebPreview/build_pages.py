"""Build the standalone web app (GitHub Pages) from WebPreview/index.html.

The Claude artifact version is published from index.html as-is; this wraps the same
page in a full document with the app icon and home-screen metadata.

Usage, from the repository root:  python -I WebPreview/build_pages.py <output-dir>
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

here = Path(__file__).resolve().parent
root = here.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)

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
    '<meta name="apple-mobile-web-app-title" content="ETF袋著走">',
    '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
    '<meta name="theme-color" content="#edf2ff">',
    '<meta name="description" content="ETF 袋著走：台灣上市 ETF 持有、配息與試算的網頁版。">',
    '<link rel="apple-touch-icon" href="apple-touch-icon.png">',
    '<link rel="icon" type="image/png" href="icon-192.png">',
    '<link rel="manifest" href="manifest.webmanifest">',
    "<style>html,body{margin:0;height:100%}</style>",
    "</head>",
    "<body>",
])
(out / "index.html").write_text(head + "\n" + "\n".join(lines) + "\n</body>\n</html>\n", encoding="utf-8")

icon = Image.open(root / "App/Assets.xcassets/Pocket.imageset/pocket.png").convert("RGB")
for name, size in [("apple-touch-icon.png", 180), ("icon-192.png", 192), ("icon-512.png", 512)]:
    icon.resize((size, size), Image.LANCZOS).save(out / name, optimize=True)

manifest = {
    "name": "ETF 袋著走",
    "short_name": "ETF袋著走",
    "lang": "zh-Hant",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "background_color": "#edf2ff",
    "theme_color": "#edf2ff",
    "icons": [
        {"src": "icon-192.png", "sizes": "192x192", "type": "image/png"},
        {"src": "icon-512.png", "sizes": "512x512", "type": "image/png"},
    ],
}
(out / "manifest.webmanifest").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
shutil.copyfile(here / "etf-data.json", out / "etf-data.json")
# Illustrations (made with Figma AI, prepared by prepare_art.py) are referenced as assets/<name>.png.
shutil.copytree(here / "assets", out / "assets", dirs_exist_ok=True)
(out / ".nojekyll").write_text("", encoding="utf-8")
print("built", sorted(p.name for p in out.iterdir()))
