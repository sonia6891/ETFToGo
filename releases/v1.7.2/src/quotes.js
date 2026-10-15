/** Same-origin, per-user quote connection. API keys are never stored in browser storage. */
import {escapeHTML as esc} from './etf-tools/finance.js';
export function createQuotes({notify,onStatus}){
 let connected=false,busy=false,timer=null,expiresAt=null,clock=null,offline=false,lastIssue='';
 const quotes=new Map(),errors=new Map();
 const stateLabels={'intraday':'盤中報價','previous-session':'前次交易日','closed':'已收盤','auction':'試撮時段・下列為末筆成交','no-trade':'尚無成交','stale':'更新較久','halted':'暫停交易','last-known':'最近成交','unknown-date':'日期待確認'};
 const fmt=new Intl.NumberFormat('zh-TW',{maximumFractionDigits:2,minimumFractionDigits:2});
 function shortTime(v){if(!v)return '時間待確認';return new Intl.DateTimeFormat('zh-TW',{timeZone:'Asia/Taipei',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date(v));}
 async function request(path,options={}){const r=await fetch(path,{credentials:'same-origin',cache:'no-store',...options,signal:AbortSignal.timeout(12000)});let d;try{d=await r.json();}catch{throw Error('連線回應格式異常。');}if(!r.ok){const e=Error(d.message||'行情暫時無法取得。');e.status=r.status;throw e;}return d;}
 function symbols(){return [...new Set([...document.querySelectorAll('[data-quote]')].map(x=>x.dataset.quote).filter(x=>/^[0-9]{4,6}[A-Z]?$/.test(x)))].slice(0,12);}
 function markup(symbol){
  if(!connected)return '<div class="q-price">—</div><div class="q-caption">尚未連接行情</div>';
  const q=quotes.get(symbol),err=errors.get(symbol);
  if(!q)return `<div class="q-price">—</div><div class="q-caption">${esc(err||'查詢中…')}</div>`;
  if(!Number.isFinite(q.price)||q.price<=0)return `<div class="q-price">—</div><div class="q-caption">${esc(err||stateLabels[q.state]||'尚無成交價')}</div>`;
  const stale=offline||!!err||(q.state==='intraday'&&Date.now()-Date.parse(q.fetchedAt)>90000);
  const delta=Number.isFinite(q.change)&&Number.isFinite(q.changePercent)?`<div class="q-delta ${q.change>0?'positive':q.change<0?'negative':''}">${q.change>0?'▲ +':q.change<0?'▼ ':''}${fmt.format(q.change)} (${q.changePercent>0?'+':''}${fmt.format(q.changePercent)}%)</div>`:'';
  return `<div class="q-price">${fmt.format(q.price)}</div>${delta}<div class="q-caption">${esc(stale?'舊報價・更新中斷':stateLabels[q.state]||'最近成交')}<br>${esc(shortTime(q.tradeAt))}</div>`;
 }
 function paint(){document.querySelectorAll('[data-quote]').forEach(el=>{el.innerHTML=markup(el.dataset.quote);});onStatus?.({connected,clock,expiresAt,offline,issue:lastIssue});}
 async function status(){try{const d=await request('/api/market/status');connected=d.connected===true;expiresAt=d.expiresAt;clock=d.clock;lastIssue='';if(!connected){quotes.clear();errors.clear();}paint();return d;}catch(e){connected=false;lastIssue=e.message;paint();return null;}}
 async function refresh(){clearTimeout(timer);if(!connected||busy||document.hidden)return;const list=symbols();if(!list.length){paint();return;}busy=true;let wait=20000;
  try{const d=await request('/api/market/quotes',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({symbols:list})});clock=d.clock;errors.clear();for(const q of d.quotes||[])if(list.includes(q.symbol))quotes.set(q.symbol,q);for(const e of d.errors||[])errors.set(e.symbol,e.message||'無法取得行情');offline=false;wait=d.retryAfter?Math.max(60000,d.retryAfter*1000):clock?.pollSeconds*1000||20000;lastIssue='';}
  catch(e){lastIssue=e.message;for(const symbol of list)errors.set(symbol,e.message);if(e.status===401){connected=false;quotes.clear();notify('行情連線已到期，請重新連接。');}wait=60000;}
  finally{busy=false;paint();if(connected&&!document.hidden)timer=setTimeout(refresh,wait);}
 }
 async function connect(key){await request('/api/market/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({apiKey:key,personalUse:true})});await status();await refresh();}
 async function disconnect(){await request('/api/market/session',{method:'DELETE'});connected=false;expiresAt=null;quotes.clear();errors.clear();clearTimeout(timer);paint();}
 function routeChanged(){paint();clearTimeout(timer);if(connected&&!busy)timer=setTimeout(refresh,350);}
 document.addEventListener('visibilitychange',()=>{clearTimeout(timer);if(!document.hidden)status().then(refresh);});
 window.addEventListener('offline',()=>{offline=true;clearTimeout(timer);paint();});window.addEventListener('online',()=>status().then(refresh));
 return {status,refresh,connect,disconnect,routeChanged,isConnected:()=>connected,getQuote:code=>quotes.get(code)};
}
