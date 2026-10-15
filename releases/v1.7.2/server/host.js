import {createQuoteApi,normalizeQuote,marketClock} from './quote-api.js';
import {createCatalogProxy} from './catalog-proxy.js';
/** Bun HTTP host, used both by the repository app and generated Railway Function. */
export async function startHost({source,version,htmlSha256,origin,referenceEndpoint}){
 const sha256=b=>new Bun.CryptoHasher('sha256').update(b).digest('hex');
 const MIME={'manifest-v172.webmanifest':'application/manifest+json; charset=utf-8','icon-192-v172.png':'image/png','icon-512-v172.png':'image/png','apple-touch-icon-v172.png':'image/png','icon-192-v171.png':'image/png','icon-512-v171.png':'image/png','apple-touch-icon-v171.png':'image/png','install-pocket.html':'text/html; charset=utf-8','icon-192-v161.png':'image/png','icon-512-v161.png':'image/png','apple-touch-icon-v161.png':'image/png','apple-touch-icon-precomposed.png':'image/png','favicon.ico':'image/x-icon','index.html':'text/html; charset=utf-8','manifest.webmanifest':'application/manifest+json; charset=utf-8','sw.js':'text/javascript; charset=utf-8','icon-192-v150.png':'image/png','icon-512-v150.png':'image/png','apple-touch-icon-v150.png':'image/png','icon-192.png':'image/png','icon-512.png':'image/png','icon-192-v141.png':'image/png','icon-512-v141.png':'image/png','apple-touch-icon-v141.png':'image/png','apple-touch-icon.png':'image/png','brand-mark.svg':'image/svg+xml; charset=utf-8','quotes.js':'text/javascript; charset=utf-8','app-v12.js':'text/javascript; charset=utf-8'};
 const assets=new Map();for(const [name,type]of Object.entries(MIME)){if(typeof source[name]!=='string'||!source[name])continue;const body=Buffer.from(source[name],/\.(png|ico)$/.test(name)?'base64':'utf8');assets.set('/'+name,{body,type,etag:'"'+sha256(body)+'"'});}
 if(!assets.has('/index.html'))throw Error('Missing main asset');
 const headers={'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Permissions-Policy':'camera=(), microphone=(), geolocation=()','Content-Security-Policy':"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; worker-src 'self'; manifest-src 'self'; object-src 'none'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'"};
 const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{...headers,'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}});
 const quoteApi=createQuoteApi({origin}),catalog=createCatalogProxy(referenceEndpoint);
 const server=Bun.serve({hostname:'::',port:Number(Bun.env.PORT||3000),maxRequestBodySize:4096,async fetch(req,server){
  const path=new URL(req.url).pathname;
  if(path==='/api/catalog'){if(!['GET','HEAD'].includes(req.method))return json({error:'METHOD'},405);const data=await catalog.get();return req.method==='HEAD'?new Response(null,{status:data.ok?200:503,headers}):json(data,data.ok?200:503);}
  if(path.startsWith('/api/market/')){const r=await quoteApi(req,server.requestIP(req)?.address||'unknown');const h=new Headers(headers);for(const [k,v]of r.headers)h.set(k,v);return new Response(r.body,{status:r.status,headers:h});}
  if(!['GET','HEAD'].includes(req.method))return json({error:'METHOD'},405);
  if(path==='/health')return req.method==='HEAD'?new Response(null,{status:200,headers}):json({ok:true,ready:true,version,assetCount:assets.size,htmlSha256,catalogue:catalog.status(),quoteMode:'personal-session-key-required',upstreamLiveTested:false});
  const normalized=(path==='/'||path==='/install-v161.html'||path==='/app-v171.html'||path==='/app-v172.html')?'/index.html':path,asset=assets.get(normalized);if(!asset)return json({error:'NOT_FOUND'},404);
  const isIcon=/\.(png|ico)$/.test(normalized);
  const versionedIcon=/-v\d+\.png$/.test(normalized);
  const h={...(isIcon?{'X-Content-Type-Options':'nosniff'}:headers),'Content-Type':asset.type,'Content-Length':String(asset.body.length),ETag:asset.etag,'Cache-Control':isIcon?(versionedIcon?'public, max-age=31536000, immutable':'public, max-age=300'):'no-cache'};
  if(normalized==='/install-pocket.html')h['Cache-Control']='no-store';
  if(normalized==='/sw.js')h['Service-Worker-Allowed']='/';
  if(!isIcon&&req.headers.get('if-none-match')===asset.etag)return new Response(null,{status:304,headers:h});
  return new Response(req.method==='HEAD'?null:asset.body,{status:200,headers:h});
 },error(){return json({error:'Service error'},500);}});
 const data=await catalog.get();const status=await(await fetch('http://[::1]:'+server.port+'/api/market/status')).json();
 const blankQuote=normalizeQuote({symbol:'0050',date:marketClock().date},'0050');
 console.log('ETF_RELEASE_CHECK',JSON.stringify({version,htmlSha256,htmlBytes:assets.get('/index.html').body.length,sourceCount:data.records?.length||0,sourceDate:data.sourceDate||null,catalogueConnected:data.ok===true,quoteEndpointReady:status.connected===false,normalizerHandlesMissingPrice:blankQuote.price===null,upstreamLiveTested:false}));
 // Verify public release paths from the deployed service, never sending credentials.
 const checks=[];for(const path of ['/health','/','/api/catalog']){try{const r=await fetch(origin+path,{signal:AbortSignal.timeout(15000),cache:'no-store'});const text=await r.text();checks.push({path,status:r.status,bytes:text.length,...(path==='/'?{ui13:text.includes('看得懂 · 算得清 · 從容記錄')}:path==='/health'?{version:JSON.parse(text).version}:{records:JSON.parse(text).records?.length})});}catch{checks.push({path,error:'Public check unavailable'});}}console.log('ETF_PUBLIC_CHECK',JSON.stringify(checks));
 return server;
}

