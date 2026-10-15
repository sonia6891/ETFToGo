/** Existing personal-session API. No credentials are written to disk or logs. */
const SYMBOL=/^[0-9]{4,6}[A-Z]?$/;
const HOLIDAYS_2026=new Set('01-01 02-12 02-13 02-15 02-16 02-17 02-18 02-19 02-20 02-27 02-28 04-03 04-04 04-05 04-06 05-01 06-19 09-25 09-28 10-09 10-10 10-25 10-26 12-25'.split(' '));
export function marketClock(now=Date.now()){
 const d=new Date(now+28800000),date=d.toISOString().slice(0,10),minute=d.getUTCHours()*60+d.getUTCMinutes(),weekend=[0,6].includes(d.getUTCDay()),knownYear=d.getUTCFullYear()===2026;
 const holiday=knownYear&&HOLIDAYS_2026.has(date.slice(5)),scheduled=!weekend&&!holiday&&minute>=540&&minute<810,settling=!weekend&&!holiday&&minute>=810&&minute<815;
 return {date,scheduled,settling,calendarVerified:knownYear,label:weekend||holiday?'例假／公告休市':settling?'收盤確認時段':scheduled?'一般交易時段（以市場公告為準）':'非一般交易時段',pollSeconds:scheduled||settling?20:300,calendarSource:'https://www.twse.com.tw/zh/trading/holiday.html',calendarCheckedAt:'2026-10-15'};
}
export function timestamp(v){if(typeof v!=='number'||!Number.isFinite(v)||v<=0)return null;const ms=v>=1e14?v/1000:v>=1e11?v:v*1000;return ms>=946684800000&&ms<7258118400000?new Date(Math.floor(ms)).toISOString():null;}
const positive=v=>typeof v==='number'&&Number.isFinite(v)&&v>0?v:null;
const finite=v=>typeof v==='number'&&Number.isFinite(v)?v:null;
export function normalizeQuote(raw,symbol,now=Date.now()){
 if(!raw||raw.symbol!==symbol||!/^\d{4}-\d{2}-\d{2}$/.test(raw.date||''))throw Error('FORMAT');
 const hasTrade=positive(raw.lastTrade?.price)!==null&&timestamp(raw.lastTrade?.time)!==null,closeValid=positive(raw.closePrice)!==null&&timestamp(raw.closeTime)!==null;
 const price=hasTrade?raw.lastTrade.price:closeValid?raw.closePrice:null,tradeAt=hasTrade?timestamp(raw.lastTrade.time):closeValid?timestamp(raw.closeTime):null;
 const reference=positive(raw.referencePrice),previousClose=positive(raw.previousClose),updatedAt=timestamp(raw.lastUpdated)||tradeAt,clock=marketClock(now),sameDay=raw.date===clock.date,updateMs=updatedAt?Date.parse(updatedAt):0,fresh=sameDay&&updateMs<=now+60000&&now-updateMs<=120000;
 let state='last-known';if(raw.tradingHalt?.isHalted)state='halted';else if(raw.date>clock.date||(tradeAt&&Date.parse(tradeAt)>now+60000))state='unknown-date';else if(!sameDay)state='previous-session';else if(raw.isClose)state='closed';else if(raw.isTrial)state='auction';else if(price===null)state='no-trade';else if((clock.scheduled||clock.settling)&&fresh)state='intraday';else if(clock.scheduled||clock.settling)state='stale';
 const change=price!==null&&reference!==null?price-reference:null;
 return {symbol,name:typeof raw.name==='string'?raw.name.slice(0,80):symbol,market:raw.market||null,date:raw.date,price,referencePrice:reference,previousClose,change,changePercent:change===null?null:100*change/reference,changeBasis:'today-reference',open:positive(raw.openPrice),high:positive(raw.highPrice),low:positive(raw.lowPrice),volume:finite(raw.total?.tradeVolume),tradeAt,sourceUpdatedAt:updatedAt,fetchedAt:new Date(now).toISOString(),state,indicativePrice:raw.isTrial?positive(raw.lastTrial?.price):null,provider:'Fugle',transport:'REST polling',cache:false};
}
export function createQuoteApi({origin,fetcher=fetch,now=Date.now,random=()=>crypto.randomUUID()+crypto.randomUUID(),hash=async key=>{const a=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key));return Array.from(new Uint8Array(a),b=>b.toString(16).padStart(2,'0')).join('');},secure=true}={}){
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
