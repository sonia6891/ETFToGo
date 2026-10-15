from pathlib import Path
import json,base64,hashlib,brotli
r=Path(__file__).resolve().parents[1]
patch=json.loads((r/'deploy/patch.json').read_text())
compiled=(r/'dist/app.check.mjs').read_text()
pos=compiled.find('const Model=(()=>{'); assert pos>0
patch.update({
 'template':(r/'src/index.html').read_text(),
 'css':(r/'src/app.css').read_text(),
 'suffix':compiled[pos:].removesuffix('})();')+'})();',
 'toolCss':(r/'src/tool-overrides.css').read_text(),
 'manifest':(r/'public/manifest.webmanifest').read_text(),
 'sw':(r/'public/sw.js').read_text(),
 'assets':{'brand-mark.svg':(r/'public/brand-mark.svg').read_text(),
 'icon-192.png':base64.b64encode((r/'public/icon-192.png').read_bytes()).decode(),
 'icon-512.png':base64.b64encode((r/'public/icon-512.png').read_bytes()).decode()}
})
# exact end-suffix should be correct from compilation without duplicated IIFE end
(r/'deploy/patch-v14.json').write_text(json.dumps(patch,ensure_ascii=False,separators=(',',':')))
raw=(r/'deploy/patch-v14.json').read_bytes();enc=base64.b64encode(brotli.compress(raw,quality=11)).decode()
parts=[enc[i:i+10000] for i in range(0,len(enc),10000)]
(r/'deploy/payload-v14.json').write_text(json.dumps({f'ETF_UI_V14_{i}':x for i,x in enumerate(parts,1)}))
for i,v in enumerate(parts,1):(r/'deploy'/f'ui-v14-{i}.txt').write_text(v)
print({'uncompressed':len(raw),'compressedB64':len(enc),'parts':len(parts),'sha256':hashlib.sha256(raw).hexdigest(),'suffixLen':len(patch['suffix'])})
