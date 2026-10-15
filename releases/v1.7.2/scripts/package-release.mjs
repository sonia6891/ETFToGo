import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {brotliCompressSync} from 'node:zlib';
let code=readFileSync('deploy/legacy-v150.ts','utf8');
const assets=Object.fromEntries(['index.html','manifest.webmanifest','sw.js','icon-192-v161.png','icon-512-v161.png','apple-touch-icon-v161.png','apple-touch-icon.png','apple-touch-icon-precomposed.png','favicon.ico'].map(f=>[f,readFileSync('dist/'+f,/\.(png|ico)$/.test(f)?'base64':'utf8')]));
const b64=brotliCompressSync(Buffer.from(JSON.stringify(assets))).toString('base64');
code=code.replace("const UI_HASH=hash(source['index.html']);",`Object.assign(source,JSON.parse(brotliDecompressSync(Buffer.from('${b64}','base64')).toString('utf8')));\nconst UI_HASH=hash(source['index.html']);`);
code=code.replaceAll("data.scope!=='twse-domestic-equity'","!['twse-domestic-equity','twse-listed'].includes(data.scope)").replaceAll("scope:'twse-domestic-equity'","scope:snapshot?.scope||'twse-listed'").replaceAll("version:'1.5.0'","version:'1.6.0'");
code=code.replace("8e048288bee8ffd955ed38da9a6fce9d3ad2365ec53af6c8f5793a03168d9000",createHash('sha256').update(assets['index.html']).digest('hex')).replace('v1.5 HTML checksum mismatch','v1.6 HTML checksum mismatch');
// Reuse public bootstrap only; backend is generated from the maintained source.
code=code.slice(0,code.indexOf('/**',code.indexOf('const UI_HASH=')));
// Cut after the known checksum guard, before bundled backend code.
const guardEnd=code.indexOf("throw Error('v1.6 HTML checksum mismatch');")+"throw Error('v1.6 HTML checksum mismatch');".length;
if(guardEnd<100)throw Error('Missing checksum guard');
code=code.slice(0,guardEnd)+'\n';
for(const file of ['quote-api.js','catalog-proxy.js','host.js']) code+=readFileSync('server/'+file,'utf8').replace(/^import .*?;\n/gm,'').replace(/\bexport /g,'')+'\n';
code+="await startHost({source,version:'1.6.1',htmlSha256:UI_HASH,origin:'https://etf-independent-app-production.up.railway.app',referenceEndpoint:'http://etf-reference-data.railway.internal:3000/catalog'});\n";
const parts=b64.match(/.{1,9000}/g);
writeFileSync('deploy/assets-v161.json',JSON.stringify(Object.fromEntries(parts.map((p,i)=>['ETF_ASSETS_V161_'+(i+1),p]))));
code=code.replace("Buffer.from('"+b64+"','base64')","Buffer.from(Array.from({length:"+parts.length+"},(_,i)=>Bun.env[`ETF_ASSETS_V161_${i+1}`]||'').join(''),'base64')");
writeFileSync('deploy/railway-v161.ts',code);
let ref=readFileSync('server/role-classifier.js','utf8').replace('export function','function')+'\n'+readFileSync('server/reference-service.js','utf8').replace("import {classifyRole} from './role-classifier.js';\n",'').replace('export {normalizeReference,createReferenceService};','').replaceAll('if(import.meta.main) ','').replace("version:'1.3.0'","version:'1.6.0'");
writeFileSync('deploy/reference-v160.ts',ref);
console.log({appBytes:Buffer.byteLength(code),referenceBytes:Buffer.byteLength(ref)});
