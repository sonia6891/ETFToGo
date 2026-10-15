import {startHost} from './host.js';
import {resolve} from 'node:path';
/** Repository entry point. All assets are built from src; no opaque asset variables required. */
const root=resolve(import.meta.dir,'../dist');
const originValue=Bun.env.APP_ORIGIN;
if(!originValue)throw Error('Set APP_ORIGIN to the exact HTTPS public origin (no path).');
const parsed=new URL(originValue);
if(parsed.protocol!=='https:'||parsed.pathname!=='/'||parsed.search||parsed.hash||parsed.username||parsed.password)throw Error('APP_ORIGIN must be one HTTPS origin.');
const referenceEndpoint=Bun.env.REFERENCE_ENDPOINT||'http://127.0.0.1:3001/catalog';
const upstream=new URL(referenceEndpoint);
if(!['http:','https:'].includes(upstream.protocol)||upstream.username||upstream.password)throw Error('Invalid reference endpoint.');
const source={};
for(const name of ['manifest-v172.webmanifest','icon-192-v172.png','icon-512-v172.png','apple-touch-icon-v172.png','icon-192-v171.png','icon-512-v171.png','apple-touch-icon-v171.png','install-pocket.html','icon-192-v161.png','icon-512-v161.png','apple-touch-icon-v161.png','apple-touch-icon-precomposed.png','favicon.ico','icon-192-v150.png','icon-512-v150.png','apple-touch-icon-v150.png','index.html','manifest.webmanifest','sw.js','icon-192.png','icon-512.png','icon-192-v141.png','icon-512-v141.png','apple-touch-icon-v141.png','apple-touch-icon.png','brand-mark.svg']){
 const file=Bun.file(resolve(root,name));if(!await file.exists())throw Error('Missing build file '+name+'; run npm run build first.');
 source[name]=/\.(png|ico)$/.test(name)?Buffer.from(await file.arrayBuffer()).toString('base64'):await file.text();
}
const htmlSha256=new Bun.CryptoHasher('sha256').update(source['index.html']).digest('hex');
await startHost({source,version:'1.7.2',htmlSha256,origin:parsed.origin,referenceEndpoint});
