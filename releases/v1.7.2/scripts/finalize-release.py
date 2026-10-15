from pathlib import Path
import json,re,hashlib,base64,brotli
r=Path(__file__).resolve().parents[1]; p=r/'deploy'
code=(p/'railway-function.ts').read_text()
old="const PATCH_HASH='ac6a128ee77a7d301e308057cd1cd73f266e33ef6147c4f288bcaa379ec6f531';"
newHash=hashlib.sha256((p/'patch-v14.json').read_bytes()).hexdigest()
assert old in code, 'unexpected original function checksum'
code=code.replace(old, f"const PATCH_HASH='{newHash}';")
assert "const parts=[1,2,3,4].map(i=>Bun.env[`ETF_UI_V13_${i}`]||'');" in code
code=code.replace("const parts=[1,2,3,4].map(i=>Bun.env[`ETF_UI_V13_${i}`]||'');", "const parts=[1,2,3,4,5].map(i=>Bun.env[`ETF_UI_V14_${i}`]||'');")
assert "source['sw.js']=patch.sw;" in code
code=code.replace("source['sw.js']=patch.sw;","""source['sw.js']=patch.sw;
for(const name of ['brand-mark.svg','icon-192.png','icon-512.png']){
 if(typeof patch.assets?.[name]!=='string'||!patch.assets[name])throw Error('Missing brand asset: '+name);
 source[name]=patch.assets[name];
}
if(!source['index.html'].includes('ETF 袋著走')||!source['index.html'].includes('成分股')||!source['manifest.webmanifest'].includes('ETF 袋著走'))throw Error('ETF ToGo build identity mismatch');""")
assert "version:'1.3.1'" in code
code=code.replace("version:'1.3.1'","version:'1.4.0'")
assert "'brand-mark.svg':'image/svg+xml; charset=utf-8'" in code
assert "path==='/api/market/holdings'" in code
assert "ETF_UI_V13_" not in code
assert "'icon-192.png'" in code
assert len(code)<38000
out=p/'railway-release.ts';out.write_text(code)
vals=json.loads((p/'payload-v14.json').read_text()); assert len(vals)==5
enc=''.join(vals[f'ETF_UI_V14_{i}'] for i in range(1,6))
raw=brotli.decompress(base64.b64decode(enc))
assert hashlib.sha256(raw).hexdigest()==newHash
body={'version':'1.4.0','projectId':'c86df9b2-4a3b-4eec-b894-c30e1a2013ba','serviceId':'3792f1a7-38ea-4d20-965d-58b1a2338520','environmentId':'456aaf6c-c42e-497b-9239-2ff4fcb195fd','variables':vals,'code':code,'patchSha256':newHash}
Path('/mnt/data/ETFToGo_v140_Railway_Release.json').write_text(json.dumps(body,ensure_ascii=False,separators=(',',':')))
print({'codeBytes':len(code.encode()),'envCount':len(vals),'envChars':len(enc),'releaseBytes':Path('/mnt/data/ETFToGo_v140_Railway_Release.json').stat().st_size,'patchSha256':newHash})
