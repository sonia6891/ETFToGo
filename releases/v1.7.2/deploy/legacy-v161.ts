import { brotliDecompressSync } from 'node:zlib';
const BASE_HASH='49dd8f4d12d419112e78279719952a3f197f4cc562b4d4247096ffdfd9c17b00';
const PATCH_HASH='464dc1aebabe4ddddc97737812b8cc2883eb73257bfff85dc12f3bd35c89113e';
const hash=b=>new Bun.CryptoHasher('sha256').update(b).digest('hex');
const base=brotliDecompressSync(Buffer.from([1,2,3,4].map(i=>Bun.env[`ETF_STATIC_BR_${i}`]||'').join(''),'base64'));
if(hash(base)!==BASE_HASH)throw Error('Base asset checksum mismatch');
const source=JSON.parse(base.toString('utf8'));
const parts=[1,2,3,4,5].map(i=>Bun.env[`ETF_UI_V14_${i}`]||'');
console.log('ETF_UI_PAYLOAD',JSON.stringify(parts.map((s,i)=>({part:i+1,length:s.length,sha256:hash(s)}))));
if(parts.some(s=>!s))throw Error('Missing UI part');
const raw=brotliDecompressSync(Buffer.from(parts.join(''),'base64'));
if(hash(raw)!==PATCH_HASH)throw Error('UI patch checksum mismatch');
const patch=JSON.parse(raw.toString('utf8')),original=source['index.html'];
const marker='<script type="module">(()=>{';
const begin=original.indexOf(marker),end=original.indexOf('\n(()=>{/** UI examples',begin);
if(begin<0||end<=begin)throw Error('Legacy component boundary changed');
let core=original.slice(begin+'<script type="module">'.length,end);
const close=core.lastIndexOf('})();');if(close<0)throw Error('Legacy IIFE boundary changed');
core='const Finance='+core.slice(0,close)+'return {'+patch.exports+'};'+core.slice(close);
const hook="const Toolkit=customElements.get('etf-planning-tools');const originalRender=Toolkit.prototype.render;Toolkit.prototype.render=function(){originalRender.call(this);const style=document.createElement('style');style.textContent="+JSON.stringify(patch.toolCss)+";this.shadowRoot.append(style);};document.querySelector('etf-planning-tools').render();\n";
const full=core+'\n'+hook+patch.suffix;
source['index.html']=patch.template.replace('/* APP_CSS */',patch.css).replace('/* APP_SCRIPT */',full.replaceAll('</script','<\\/script'));
source['manifest.webmanifest']=patch.manifest;
source['sw.js']=patch.sw;
for(const name of ['brand-mark.svg','icon-192.png','icon-512.png']){
 if(typeof patch.assets?.[name]!=='string'||!patch.assets[name])throw Error('Missing brand asset: '+name);
 source[name]=patch.assets[name];
}
// 1.4.1 iOS/PWA home-screen icon cache fix. Does not touch user storage or broker/quote sessions.
const iconParts=[1,2,3,4,5,6,7,8,9,10,11,12].map(i=>Bun.env[`ETF_ICON_V141_${i}`]||'');
if(iconParts.some(p=>!p))throw Error('Missing 1.4.1 icon assets');
const iconRaw=brotliDecompressSync(Buffer.from(iconParts.join(''),'base64'));
if(hash(iconRaw)!=='12d64cdb06c92ff468084fdd6ed27a4f688f204c53350bd37625b95f107ca7db')throw Error('1.4.1 icon bundle checksum mismatch');
const iconFix=JSON.parse(iconRaw.toString('utf8'));
if(iconFix.version!=='1.4.1')throw Error('Icon version mismatch');
const replacements=[iconFix.htmlReplace.apple,iconFix.htmlReplace.favicon,iconFix.htmlReplace.manifest];
for(const pair of replacements){
 if(!Array.isArray(pair)||pair.length!==2||!source['index.html'].includes(pair[0]))throw Error('Icon HTML link not found');
 source['index.html']=source['index.html'].replace(pair[0],pair[1]);
}
if(!source['index.html'].includes('src="./brand-mark.svg"'))throw Error('Header brand image missing');
source['index.html']=source['index.html'].replace('src="./brand-mark.svg"','src="./icon-192-v141.png"');
source['manifest.webmanifest']=iconFix.manifest;
source['sw.js']=iconFix.sw;
for(const name of ['icon-192-v141.png','icon-512-v141.png','apple-touch-icon-v141.png','apple-touch-icon.png']){
 if(typeof iconFix.assets?.[name]!=='string'||!iconFix.assets[name])throw Error('Icon PNG missing: '+name);
 source[name]=iconFix.assets[name];
}
// Preserve old endpoints for existing browsers, while new links bypass their cached URLs.
source['icon-192.png']=iconFix.assets['icon-192-v141.png'];
source['icon-512.png']=iconFix.assets['icon-512-v141.png'];
if(!source['index.html'].includes('ETF 袋著走')||!source['index.html'].includes('成分股')||!source['manifest.webmanifest'].includes('ETF 袋著走'))throw Error('ETF ToGo build identity mismatch');
// Existing tabs can still request old script URLs; the new shell does not run them.
for(const [file,key]of [['quotes.js','ETF_QUOTES_CLIENT_BR'],['app-v12.js','ETF_APP_V12_BR']]){if(Bun.env[key])source[file]=brotliDecompressSync(Buffer.from(Bun.env[key],'base64')).toString('utf8');}
// Functional mobile interface refresh: replace rendered HTML/CSS with tested 1.5.0 UI.
// Existing server API and localStorage schema stay unchanged.
const ui15Parts=Array.from({length:18},(_,i)=>Bun.env[`ETF_UI_V150_${i+1}`]||'');
if(ui15Parts.some(x=>!x))throw Error('Missing v1.5 functional UI assets');
const ui15Raw=brotliDecompressSync(Buffer.from(ui15Parts.join(''),'base64'));
if(hash(ui15Raw)!=='b7e50fc84069c57584b8bcdf1a42a834d22086de5b106ad17d8a2016ddb59cdb')throw Error('v1.5 UI checksum mismatch');
const ui15=JSON.parse(ui15Raw.toString('utf8'));
for(const name of ['index.html','manifest.webmanifest','sw.js','icon-192-v150.png','icon-512-v150.png','apple-touch-icon-v150.png']){
 if(typeof ui15[name]!=='string'||!ui15[name])throw Error('Missing v1.5 asset '+name);
 source[name]=ui15[name];
}
if(!source['index.html'].includes('你的 ETF，都在這裡。')||!source['index.html'].includes('apple-touch-icon-v150.png')||source['index.html'].includes('你的 ETF，今天也整理好了。'))throw Error('Functional mobile UI signature mismatch');
Object.assign(source,JSON.parse(brotliDecompressSync(Buffer.from(Array.from({length:29},(_,i)=>Bun.env[`ETF_ASSETS_V161_${i+1}`]||'').join(''),'base64')).toString('utf8')));
const UI_HASH=hash(source['index.html']);
if(UI_HASH!=='674be69a794cf60b29a00c2b901ce197e8a747f4cb9fd6ed07fed9ccd504f463')throw Error('v1.6 HTML checksum mismatch');
/** Existing personal-session API. No credentials are written to disk or logs. */
const SYMBOL=/^[0-9]{4,6}[A-Z]?$/;
const HOLIDAYS_2026=new Set('01-01 02-12 02-13 02-15 02-16 02-17 02-18 02-19 02-20 02-27 02-28 04-03 04-04 04-05 04-06 05-01 06-19 09-25 09-28 10-09 10-10 10-25 10-26 12-25'.split(' '));
function marketClock(now=Date.now()){
 const d=new Date(now+28800000),date=d.toISOString().slice(0,10),minute=d.getUTCHours()*60+d.getUTCMinutes(),weekend=[0,6].includes(d.getUTCDay()),knownYear=d.getUTCFullYear()===2026;
 const holiday=knownYear&&HOLIDAYS_2026.has(date.slice(5)),scheduled=!weekend&&!holiday&&minute>=540&&minute<810,settling=!weekend&&!holiday&&minute>=810&&minute<815;
 return {date,scheduled,settling,calendarVerified:knownYear,label:weekend||holiday?'例假／公告休市':settling?'收盤確認時段':scheduled?'一般交易時段（以市場公告為準）':'非一般交易時段',pollSeconds:scheduled||settling?20:300,calendarSource:'https://www.twse.com.tw/zh/trading/holiday.html',calendarCheckedAt:'2026-10-15'};
}
function timestamp(v){if(typeof v!=='number'||!Number.isFinite(v)||v<=0)return null;const ms=v>=1e14?v/1000:v>=1e11?v:v*1000;return ms>=946684800000&&ms<7258118400000?new Date(Math.floor(ms)).toISOString():null;}
const positive=v=>typeof v==='number'&&Number.isFinite(v)&&v>0?v:null;
const finite=v=>typeof v==='number'&&Number.isFinite(v)?v:null;
function normalizeQuote(raw,symbol,now=Date.now()){
 if(!raw||raw.symbol!==symbol||!/^\d{4}-\d{2}-\d{2}$/.test(raw.date||''))throw Error('FORMAT');
 const hasTrade=positive(raw.lastTrade?.price)!==null&&timestamp(raw.lastTrade?.time)!==null,closeValid=positive(raw.closePrice)!==null&&timestamp(raw.closeTime)!==null;
 const price=hasTrade?raw.lastTrade.price:closeValid?raw.closePrice:null,tradeAt=hasTrade?timestamp(raw.lastTrade.time):closeValid?timestamp(raw.closeTime):null;
 const reference=positive(raw.referencePrice),previousClose=positive(raw.previousClose),updatedAt=timestamp(raw.lastUpdated)||tradeAt,clock=marketClock(now),sameDay=raw.date===clock.date,updateMs=updatedAt?Date.parse(updatedAt):0,fresh=sameDay&&updateMs<=now+60000&&now-updateMs<=120000;
 let state='last-known';if(raw.tradingHalt?.isHalted)state='halted';else if(raw.date>clock.date||(tradeAt&&Date.parse(tradeAt)>now+60000))state='unknown-date';else if(!sameDay)state='previous-session';else if(raw.isClose)state='closed';else if(raw.isTrial)state='auction';else if(price===null)state='no-trade';else if((clock.scheduled||clock.settling)&&fresh)state='intraday';else if(clock.scheduled||clock.settling)state='stale';
 const change=price!==null&&reference!==null?price-reference:null;
 return {symbol,name:typeof raw.name==='string'?raw.name.slice(0,80):symbol,market:raw.market||null,date:raw.date,price,referencePrice:reference,previousClose,change,changePercent:change===null?null:100*change/reference,changeBasis:'today-reference',open:positive(raw.openPrice),high:positive(raw.highPrice),low:positive(raw.lowPrice),volume:finite(raw.total?.tradeVolume),tradeAt,sourceUpdatedAt:updatedAt,fetchedAt:new Date(now).toISOString(),state,indicativePrice:raw.isTrial?positive(raw.lastTrial?.price):null,provider:'Fugle',transport:'REST polling',cache:false};
}
function createQuoteApi({origin,fetcher=fetch,now=Date.now,random=()=>crypto.randomUUID()+crypto.randomUUID(),hash=async key=>{const a=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key));return Array.from(new Uint8Array(a),b=>b.toString(16).padStart(2,'0')).join('');},secure=true}={}){
 if(!origin)throw Error('Explicit app origin required');
 const sessions=new Map(),keyBudgets=new Map(),attempts=new Map(),ttl=6*60*60*1000,cookieName=secure?'__Host-etf_quote':'etf_quote_dev';
 const errors={KEY:'富果回覆金鑰無效（401）。請確認使用的是「台股行情 v1.0」API Key，而不是舊版 v0.3 或交易 API 金鑰。',PERMISSION:'富果回覆 403：金鑰存在但此服務可能沒有行情使用權限，請確認方案或洽富果。',RATE:'富果／本站呼叫額度暫時受限（429），請稍後再試。',SYMBOL:'供應商找不到此代碼的行情。',UPSTREAM:'目前連不到富果服務，尚無法判定金鑰是否有效。請稍後重試。',FORMAT:'富果資料格式與預期不同，已停止使用該筆資料；不代表金鑰無效。'};
 function sweep(){const n=now();for(const [id,s]of sessions)if(s.expires<=n){s.key='';s.cache.clear();clearTimeout(s.timer);sessions.delete(id);}for(const [id,b]of keyBudgets)if(n-b.last>ttl)keyBudgets.delete(id);for(const [id,b]of attempts)if(n-b.since>600000)attempts.delete(id);}
 function session(req){const id=req.headers.get('cookie')?.split(';').map(x=>x.trim()).find(x=>x.startsWith(cookieName+'='))?.slice(cookieName.length+1);return id?sessions.get(id):null;}
 function cookie(id='',age=0){return `${cookieName}=${id}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}${secure?'; Secure':''}`;}
 function reply(data,status=200,extra={}){return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'private, no-store, max-age=0',Pragma:'no-cache','X-Content-Type-Options':'nosniff',Vary:'Cookie',...extra}});}
 function budgetFor(keyId){let b=keyBudgets.get(keyId);if(!b){b={calls:[],blockedUntil:0,last:now()};keyBudgets.set(keyId,b);}b.last=now();return b;}
 async function upstream(s,symbol){
  const n=now(),cached=s.cache.get(symbol),clock=marketClock(n),cacheMs=(clock.scheduled||clock.settling)?19000:60000;
  if(cached&&n-cached.at<cacheMs)return {...cached.q,cache:true};if(s.pending.has(symbol))return s.pending.get(symbol);
  const b=budgetFor(s.keyId);b.calls=b.calls.filter(t=>n-t<60000);if(b.blockedUntil>n||b.calls.length>=48)throw Error('RATE');b.calls.push(n);
  const work=(async()=>{let r;try{r=await fetcher('https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/'+symbol,{headers:{'X-API-KEY':s.key,Accept:'application/json'},signal:AbortSignal.timeout(8000),redirect:'error'});}catch{throw Error('UPSTREAM');}
   if(r.status===401)throw Error('KEY');if(r.status===403)throw Error('PERMISSION');if(r.status===429){b.blockedUntil=now()+60000;throw Error('RATE');}if(r.status===404)throw Error('SYMBOL');if(!r.ok)throw Error('UPSTREAM');let raw;try{raw=await r.json();}catch{throw Error('FORMAT');}const q=normalizeQuote(raw,symbol,now());s.cache.set(symbol,{q,at:now()});if(s.cache.size>120)s.cache.delete(s.cache.keys().next().value);return q;})();
  s.pending.set(symbol,work);try{return await work;}finally{s.pending.delete(symbol);}
 }
 // Verify API credentials using a lightweight official ticker metadata endpoint.
 // Quote payloads can be unavailable or incomplete outside market hours; that is NOT a failed key.
 async function verifyKey(s){
  let response;
  try {response=await fetcher('https://api.fugle.tw/marketdata/v1.0/stock/intraday/ticker/0050', {headers:{'X-API-KEY':s.key,Accept:'application/json'},signal:AbortSignal.timeout(9500),redirect:'error'});}
  catch {throw Error('UPSTREAM');}
  if(response.status===401)throw Error('KEY');
  if(response.status===403)throw Error('PERMISSION');
  if(response.status===429)throw Error('RATE');
  if(!response.ok)throw Error('UPSTREAM');
  let raw;try{raw=await response.json();}catch{throw Error('FORMAT');}
  if(!raw||String(raw.symbol||'')!=='0050')throw Error('FORMAT');
 }
 return async function quoteApi(req,clientId='unknown'){
  sweep();const path=new URL(req.url).pathname;if(!path.startsWith('/api/market/'))return null;
  if(path==='/api/market/status'&&req.method==='GET'){const s=session(req);return reply({connected:!!s,expiresAt:s?new Date(s.expires).toISOString():null,provider:'Fugle',scope:'personal-session',clock:marketClock(now()),pollSeconds:20,maxSymbols:12,serverTime:new Date(now()).toISOString(),needsPersonalKey:!s});}
  if(!['POST','DELETE'].includes(req.method))return reply({error:'METHOD',message:'不支援此方法。'},405);
  if(req.headers.get('origin')!==origin||req.headers.get('sec-fetch-site')==='cross-site')return reply({error:'ORIGIN',message:'請從原 App 網址操作。'},403);
  if(path==='/api/market/session'&&req.method==='DELETE'){const s=session(req);if(s){s.key='';s.cache.clear();clearTimeout(s.timer);sessions.delete(s.id);}return reply({connected:false},200,{'Set-Cookie':cookie()});}
  if(!req.headers.get('content-type')?.startsWith('application/json'))return reply({error:'CONTENT_TYPE'},415);
  if(Number(req.headers.get('content-length')||0)>4096)return reply({error:'TOO_LARGE'},413);
  let data;try{const text=await req.text();if(text.length>4096)return reply({error:'TOO_LARGE'},413);data=JSON.parse(text);}catch{return reply({error:'JSON',message:'請檢查輸入格式。'},400);}
  if(path==='/api/market/session'&&req.method==='POST'){
   let a=attempts.get(clientId);if(!a){if(attempts.size>=2000)return reply({error:'BUSY'},503);a={since:now(),count:0};attempts.set(clientId,a);}if(++a.count>5)return reply({error:'RATE',message:'嘗試連線過於頻繁，請十分鐘後重試。'},429,{'Retry-After':'600'});
   const key=typeof data.apiKey==='string'?data.apiKey.trim():'';if(!/^[\x21-\x7E]{8,1024}$/.test(key)||data.personalUse!==true)return reply({error:'INPUT',message:'請填入有效的個人行情金鑰，並確認使用規範。'},400);
   if(sessions.size>=100)return reply({error:'BUSY',message:'目前連線已滿，請稍後再試。'},503);
   const id=random(),s={id,key,keyId:await hash(key),expires:now()+ttl,cache:new Map(),pending:new Map()};
   try{await verifyKey(s);}catch(e){s.key='';const code=errors[e.message]?e.message:'UPSTREAM';return reply({error:code,message:errors[code],stage:'credential-validation',hint:'先確認是否為台股行情 API v1.0 金鑰；若富果 API 可用但本站連不到，請稍候再試。'},code==='KEY'?401:code==='PERMISSION'?403:code==='RATE'?429:502);}
   const old=session(req);if(old){old.key='';old.cache.clear();clearTimeout(old.timer);sessions.delete(old.id);}sessions.set(id,s);s.timer=setTimeout(()=>{s.key='';s.cache.clear();sessions.delete(id);},ttl);s.timer.unref?.();return reply({connected:true,expiresAt:new Date(s.expires).toISOString(),provider:'Fugle'},200,{'Set-Cookie':cookie(id,ttl/1000)});
  }
  if(path==='/api/market/holdings'&&req.method==='POST'){
   const s=session(req);if(!s)return reply({error:'NOT_CONNECTED',message:'請先連接個人富果行情金鑰。'},401);
   const symbol=String(data.symbol||'');
   if(!SYMBOL.test(symbol))return reply({error:'SYMBOL',message:'ETF 代碼格式不正確。'},400);
   const cacheKey='holdings:'+symbol,n=now(),cached=s.cache.get(cacheKey);
   if(cached&&n-cached.at<1800000)return reply({...cached.q,cached:true});
   const b=budgetFor(s.keyId);b.calls=b.calls.filter(t=>n-t<60000);
   if(b.blockedUntil>n||b.calls.length>=48)return reply({error:'RATE',message:errors.RATE},429);
   b.calls.push(n);
   let upstreamResponse;
   try{upstreamResponse=await fetcher('https://api.fugle.tw/marketdata/v1.0/stock/ownership/etf-holdings/'+symbol,{headers:{'X-API-KEY':s.key,Accept:'application/json'},signal:AbortSignal.timeout(12000),redirect:'error'});}
   catch{return reply({error:'UPSTREAM',message:errors.UPSTREAM},502);}
   if(upstreamResponse.status===403)return reply({error:'PLAN_REQUIRED',message:'成分股 API 屬富果「開發者／進階方案」，目前金鑰無此權限；行情連線仍可正常使用。',providerLink:'https://developer.fugle.tw/docs/data/http-api/ownership/etf-holdings/'},403);
   if(upstreamResponse.status===401)return reply({error:'KEY',message:'富果對成分股查詢回覆 401，請重新確認金鑰；不影響已記錄持有。'},401);
   if(upstreamResponse.status===429){b.blockedUntil=now()+60000;return reply({error:'RATE',message:errors.RATE},429);}
   if(upstreamResponse.status===404)return reply({error:'NOT_FOUND',message:'富果尚未提供這檔 ETF 的成分股明細。'},404);
   if(!upstreamResponse.ok)return reply({error:'UPSTREAM',message:'無法取得成分股資料，請稍後再試。'},502);
   let raw;try{raw=await upstreamResponse.json();}catch{return reply({error:'FORMAT',message:errors.FORMAT},502);}
   if(raw?.symbol!==symbol||!Array.isArray(raw.data)||raw.data.length===0)return reply({error:'NO_DATA',message:'這檔 ETF 目前沒有可用的成分股公告。'},404);
   const latest=[...raw.data].filter(d=>/^\d{4}-\d{2}-\d{2}$/.test(d?.date||'')&&Array.isArray(d?.components)).sort((a,b)=>b.date.localeCompare(a.date))[0];
   if(!latest||latest.date>marketClock(now()).date)return reply({error:'FORMAT',message:'成分股公告日期異常，已拒絕資料。'},502);
   const holdings=latest.components;if(holdings.length>1000||!holdings.length)return reply({error:'FORMAT',message:'成分股數量超出預期。'},502);
   const seen=new Set(),components=[];let sum=0;
   for(const h of holdings){const code=String(h?.symbol||''),weight=Number(h?.weight);
    if(!/^[A-Za-z0-9.\-]{1,15}$/.test(code)||seen.has(code)||typeof h?.name!=='string'||h.name.length>120||!Number.isFinite(weight)||weight<0||weight>100)return reply({error:'FORMAT',message:'成分股欄位未通過驗證。'},502);
    seen.add(code);sum+=weight;components.push({symbol:code,name:h.name,weight,quantity:typeof h.quantity==='number'&&Number.isFinite(h.quantity)&&h.quantity>=0?h.quantity:null});
   }
   if(sum>110)return reply({error:'FORMAT',message:'成分股權重加總異常。'},502);
   components.sort((a,b)=>b.weight-a.weight);
   const payload={symbol,date:latest.date,components,totalWeight:sum,source:'富果 ETF Holdings',fetchedAt:new Date(now()).toISOString(),coverage:sum>=97?'reported-holdings':'partial-report',cached:false};
   s.cache.set(cacheKey,{q:payload,at:now()});return reply(payload);
  }
  if(path==='/api/market/quotes'&&req.method==='POST'){
   const s=session(req);if(!s)return reply({error:'NOT_CONNECTED',message:'請先連接你自己的行情金鑰。'},401);
   if(!Array.isArray(data.symbols)||data.symbols.length>12||data.symbols.some(x=>typeof x!=='string'||!SYMBOL.test(x)))return reply({error:'SYMBOLS',message:'每次最多查詢12個有效證券代碼。'},400);
   const symbols=[...new Set(data.symbols)],quotes=[],failed=[];let cursor=0;const worker=async()=>{while(cursor<symbols.length){const symbol=symbols[cursor++];try{quotes.push(await upstream(s,symbol));}catch(e){failed.push({symbol,error:e.message,message:errors[e.message]||errors.UPSTREAM});}}};await Promise.all(Array.from({length:Math.min(3,symbols.length)},worker));
   if(failed.some(x=>x.error==='KEY'||x.error==='PERMISSION')){s.key='';clearTimeout(s.timer);sessions.delete(s.id);return reply({error:'KEY',message:errors.KEY},401,{'Set-Cookie':cookie()});}return reply({quotes,errors:failed,clock:marketClock(now()),serverTime:new Date(now()).toISOString(),retryAfter:failed.some(x=>x.error==='RATE')?60:null});
  }
  return reply({error:'NOT_FOUND'},404);
 };
}

/** Proxy only public metadata. It never forwards cookies, API keys or personal records. */
function createCatalogProxy(endpoint,fetcher=fetch,now=Date.now){
 let snapshot=null,pending=null,checked=0,error=null;
 const current=()=>snapshot?{...snapshot,stale:!!error||snapshot.stale,warning:error?'最新同步暫時失敗，保留上次成功版本。':snapshot.warning}:{ok:false,error:'REFERENCE_UNAVAILABLE',records:[]};
 async function get(){if(pending)return pending;if(checked&&now()-checked<60000)return current();checked=now();pending=(async()=>{try{const r=await fetcher(endpoint,{headers:{Accept:'application/json'},signal:AbortSignal.timeout(22000),redirect:'error'});if(!r.ok)throw Error('REFERENCE_HTTP_'+r.status);const text=await r.text();if(text.length>2000000)throw Error('REFERENCE_TOO_LARGE');const data=JSON.parse(text);if(data.ok!==true||data.version!==1||!['twse-domestic-equity','twse-listed'].includes(data.scope)||!Array.isArray(data.records)||!data.records.length||data.records.length>1000||!/^\d{4}-\d{2}-\d{2}$/.test(data.sourceDate))throw Error('REFERENCE_SCHEMA');if(snapshot&&data.sourceDate<snapshot.sourceDate)throw Error('REFERENCE_REGRESSION');snapshot=data;error=null;}catch(e){error=String(e.message).slice(0,120);console.log('REFERENCE_PROXY_WARNING',error);}finally{pending=null;}return current();})();return pending;}
 return {get,status:()=>({connected:!!snapshot,sourceDate:snapshot?.sourceDate||null,count:snapshot?.records.length||0,scope:snapshot?.scope||'twse-listed',stale:!!error||!!snapshot?.stale})};
}

/** Bun HTTP host, used both by the repository app and generated Railway Function. */
async function startHost({source,version,htmlSha256,origin,referenceEndpoint}){
 const sha256=b=>new Bun.CryptoHasher('sha256').update(b).digest('hex');
 const MIME={'icon-192-v161.png':'image/png','icon-512-v161.png':'image/png','apple-touch-icon-v161.png':'image/png','apple-touch-icon-precomposed.png':'image/png','favicon.ico':'image/x-icon','index.html':'text/html; charset=utf-8','manifest.webmanifest':'application/manifest+json; charset=utf-8','sw.js':'text/javascript; charset=utf-8','icon-192-v150.png':'image/png','icon-512-v150.png':'image/png','apple-touch-icon-v150.png':'image/png','icon-192.png':'image/png','icon-512.png':'image/png','icon-192-v141.png':'image/png','icon-512-v141.png':'image/png','apple-touch-icon-v141.png':'image/png','apple-touch-icon.png':'image/png','brand-mark.svg':'image/svg+xml; charset=utf-8','quotes.js':'text/javascript; charset=utf-8','app-v12.js':'text/javascript; charset=utf-8'};
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
  const normalized=(path==='/'||path==='/install-v161.html')?'/index.html':path,asset=assets.get(normalized);if(!asset)return json({error:'NOT_FOUND'},404);
  const h={...headers,'Content-Type':asset.type,ETag:asset.etag,'Cache-Control':/\.(png|ico)$/.test(normalized)?'no-cache, max-age=0, must-revalidate':'no-cache'};if(normalized==='/sw.js')h['Service-Worker-Allowed']='/';if(req.headers.get('if-none-match')===asset.etag)return new Response(null,{status:304,headers:h});return new Response(req.method==='HEAD'?null:asset.body,{status:200,headers:h});
 },error(){return json({error:'Service error'},500);}});
 const data=await catalog.get();const status=await(await fetch('http://[::1]:'+server.port+'/api/market/status')).json();
 const blankQuote=normalizeQuote({symbol:'0050',date:marketClock().date},'0050');
 console.log('ETF_RELEASE_CHECK',JSON.stringify({version,htmlSha256,htmlBytes:assets.get('/index.html').body.length,sourceCount:data.records?.length||0,sourceDate:data.sourceDate||null,catalogueConnected:data.ok===true,quoteEndpointReady:status.connected===false,normalizerHandlesMissingPrice:blankQuote.price===null,upstreamLiveTested:false}));
 // Verify public release paths from the deployed service, never sending credentials.
 const checks=[];for(const path of ['/health','/','/api/catalog']){try{const r=await fetch(origin+path,{signal:AbortSignal.timeout(15000),cache:'no-store'});const text=await r.text();checks.push({path,status:r.status,bytes:text.length,...(path==='/'?{ui13:text.includes('看得懂 · 算得清 · 從容記錄')}:path==='/health'?{version:JSON.parse(text).version}:{records:JSON.parse(text).records?.length})});}catch{checks.push({path,error:'Public check unavailable'});}}console.log('ETF_PUBLIC_CHECK',JSON.stringify(checks));
 return server;
}

await startHost({source,version:'1.6.1',htmlSha256:UI_HASH,origin:'https://etf-independent-app-production.up.railway.app',referenceEndpoint:'http://etf-reference-data.railway.internal:3000/catalog'});

