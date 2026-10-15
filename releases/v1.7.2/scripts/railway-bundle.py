"""Build Railway's 1.3 migration function; public UI payload only, never API keys.
The old immutable shell supplies the unchanged finance component during rollout.
For a fresh GitHub checkout use server/index.js instead; no legacy payload required.
"""
from pathlib import Path
import brotli,base64,hashlib,re,json
root=Path(__file__).resolve().parents[1]
# patch.json is the frozen rollout payload validated by tests/browser.py.
build=root/'deploy';raw=(build/'patch.json').read_bytes();digest=hashlib.sha256(raw).hexdigest()
encoded=base64.b64encode(brotli.compress(raw,quality=11)).decode()
parts=[encoded[i:i+8000] for i in range(0,len(encoded),8000)]
for i,part in enumerate(parts,1):(build/f'ui-payload-{i}.txt').write_text(part)
(build/'ui-payload.json').write_text(json.dumps({f'ETF_UI_V13_{i}':p for i,p in enumerate(parts,1)}))
head="""import { brotliDecompressSync } from 'node:zlib';
const BASE_HASH='49dd8f4d12d419112e78279719952a3f197f4cc562b4d4247096ffdfd9c17b00';
const PATCH_HASH='__PATCH_HASH__';
const hash=b=>new Bun.CryptoHasher('sha256').update(b).digest('hex');
const base=brotliDecompressSync(Buffer.from([1,2,3,4].map(i=>Bun.env[`ETF_STATIC_BR_${i}`]||'').join(''),'base64'));
if(hash(base)!==BASE_HASH)throw Error('Base asset checksum mismatch');
const source=JSON.parse(base.toString('utf8'));
const parts=[1,2,3,4].map(i=>Bun.env[`ETF_UI_V13_${i}`]||'');
console.log('ETF_UI_PAYLOAD',JSON.stringify(parts.map((s,i)=>({part:i+1,length:s.length,sha256:hash(s)}))));
if(parts.some(s=>!s))throw Error('Missing UI part');
const raw=brotliDecompressSync(Buffer.from(parts.join(''),'base64'));
if(hash(raw)!==PATCH_HASH)throw Error('UI patch checksum mismatch');
const patch=JSON.parse(raw.toString('utf8')),original=source['index.html'];
const marker='<script type="module">(()=>{';
const begin=original.indexOf(marker),end=original.indexOf('\\n(()=>{/** UI examples',begin);
if(begin<0||end<=begin)throw Error('Legacy component boundary changed');
let core=original.slice(begin+'<script type="module">'.length,end);
const close=core.lastIndexOf('})();');if(close<0)throw Error('Legacy IIFE boundary changed');
core='const Finance='+core.slice(0,close)+'return {'+patch.exports+'};'+core.slice(close);
const hook="const Toolkit=customElements.get('etf-planning-tools');const originalRender=Toolkit.prototype.render;Toolkit.prototype.render=function(){originalRender.call(this);const style=document.createElement('style');style.textContent="+JSON.stringify(patch.toolCss)+";this.shadowRoot.append(style);};document.querySelector('etf-planning-tools').render();\\n";
const full=core+'\\n'+hook+patch.suffix;
source['index.html']=patch.template.replace('/* APP_CSS */',patch.css).replace('/* APP_SCRIPT */',full.replaceAll('</script','<\\\\/script'));
source['manifest.webmanifest']=patch.manifest;
source['sw.js']=patch.sw;
// Existing tabs can still request old script URLs; the new shell does not run them.
for(const [file,key]of [['quotes.js','ETF_QUOTES_CLIENT_BR'],['app-v12.js','ETF_APP_V12_BR']]){if(Bun.env[key])source[file]=brotliDecompressSync(Buffer.from(Bun.env[key],'base64')).toString('utf8');}
const UI_HASH=hash(source['index.html']);
""".replace('__PATCH_HASH__',digest)
code=head
for name in ['quote-api.js','catalog-proxy.js','host.js']:
 s=(root/'server'/name).read_text();s=re.sub(r'^import .*?;\n','',s,flags=re.M);s=s.replace('export ','');code+='\n'+s
code+="\nawait startHost({source,version:'1.3.1',htmlSha256:UI_HASH,origin:'https://etf-independent-app-production.up.railway.app',referenceEndpoint:'http://etf-reference-data.railway.internal:3000/catalog'});\n"
(build/'railway-function.ts').write_text(code)
(build/'railway-check.mjs').write_text(code)
print(json.dumps({'patchBytes':len(raw),'patchSha256':digest,'payloadLength':len(encoded),'parts':len(parts),'functionBytes':len(code.encode())}))
