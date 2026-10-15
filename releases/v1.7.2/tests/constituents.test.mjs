import {test} from 'node:test';import assert from 'node:assert/strict';import {createQuoteApi} from '../server/quote-api.js';
const origin='https://etftogo.test';
function create(fetcher){return createQuoteApi({origin,secure:false,fetcher,now:()=>Date.parse('2026-10-15T04:00:00Z')});}
const consent=()=>new Request(origin+'/api/market/session',{method:'POST',headers:{origin,'Content-Type':'application/json'},body:JSON.stringify({apiKey:'test-random-abcdef-012345',personalUse:true})});
const holding=(cookie,symbol='0050')=>new Request(origin+'/api/market/holdings',{method:'POST',headers:{origin,'Content-Type':'application/json',Cookie:cookie},body:JSON.stringify({symbol})});
async function connect(api){const r=await api(consent(),'test-ip');assert.equal(r.status,200);return r.headers.get('set-cookie').split(';')[0];}
test('ETF constituent endpoint cannot be accessed without personal session',async()=>{let called=0;const api=create(async()=>{called++;return Response.json({});});const r=await api(holding(''));assert.equal(r.status,401);assert.equal(called,0);});
test('stock constituent query returns actual sourced rows and date',async()=>{
 const calls=[];const api=create(async url=>{calls.push(url);if(url.includes('/ticker/0050'))return Response.json({symbol:'0050'});return Response.json({symbol:'0050',data:[{date:'2026-10-14',components:[{symbol:'2330',name:'台積電',weight:60.2,quantity:12345},{symbol:'2454',name:'聯發科',weight:5.1,quantity:4567}]}]});});const c=await connect(api);const r=await api(holding(c));assert.equal(r.status,200);const j=await r.json();assert.equal(j.date,'2026-10-14');assert.equal(j.components[0].symbol,'2330');assert.equal(j.totalWeight,65.3);assert.equal(j.coverage,'partial-report');assert.equal(calls.length,2);
 const cached=await api(holding(c));assert.equal(cached.status,200);assert.equal((await cached.json()).cached,true);assert.equal(calls.length,2);
});
test('Fugle basic plan missing entitlement returns clear 403 without disconnecting quotes',async()=>{
 const api=create(async url=>url.includes('/ticker/0050')?Response.json({symbol:'0050'}):Response.json({error:'forbidden'},{status:403}));const cookie=await connect(api);const r=await api(holding(cookie));assert.equal(r.status,403);assert.equal((await r.json()).error,'PLAN_REQUIRED');const s=await api(new Request(origin+'/api/market/status',{headers:{Cookie:cookie}}));assert.equal((await s.json()).connected,true);
});
test('future-dated or oversized constituents are rejected instead of simulated',async()=>{
 const api=create(async url=>url.includes('/ticker/0050')?Response.json({symbol:'0050'}):Response.json({symbol:'0050',data:[{date:'2099-01-01',components:[{symbol:'2330',name:'台積電',weight:60}]}]}));const cookie=await connect(api);const r=await api(holding(cookie));assert.equal(r.status,502);assert.equal((await r.json()).error,'FORMAT');
});
