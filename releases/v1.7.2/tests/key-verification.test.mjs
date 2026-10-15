import {test} from 'node:test';import assert from 'node:assert/strict';import {createQuoteApi} from '../server/quote-api.js';
const origin='https://example.test';
const request=(key)=>new Request(origin+'/api/market/session',{method:'POST',headers:{'Origin':origin,'Content-Type':'application/json'},body:JSON.stringify({apiKey:key,personalUse:true})});
test('valid key accepts ticker metadata even without intraday quote during non-trading hours',async()=>{
 const calls=[];const api=createQuoteApi({origin,secure:false,fetcher:async(url)=>{calls.push(url);assert.match(url,/\/intraday\/ticker\/0050$/);return Response.json({symbol:'0050',name:'元大台灣50'});}});
 const r=await api(request('abc_VALID_FUGLE_KEY_123'),'test-ip');assert.equal(r.status,200);assert.equal((await r.json()).connected,true);assert.equal(calls.length,1);assert.match(r.headers.get('set-cookie'),/HttpOnly/);
});
test('401 means rejected v1 key, not provider down',async()=>{
 const api=createQuoteApi({origin,secure:false,fetcher:async()=>Response.json({}, {status:401})});const r=await api(request('abc_VALID_FUGLE_KEY_123'),'ip-2');assert.equal(r.status,401);const d=await r.json();assert.equal(d.error,'KEY');assert.match(d.message,/v1.0/);
});
test('403 means missing permission not necessarily invalid key',async()=>{
 const api=createQuoteApi({origin,secure:false,fetcher:async()=>Response.json({}, {status:403})});const r=await api(request('abc_VALID_FUGLE_KEY_123'),'ip-3');assert.equal(r.status,403);assert.equal((await r.json()).error,'PERMISSION');
});
test('provider timeout is marked unverifiable, not an invalid key',async()=>{
 const api=createQuoteApi({origin,secure:false,fetcher:async()=>{throw new Error('timeout')}});const r=await api(request('abc_VALID_FUGLE_KEY_123'),'ip-4');assert.equal(r.status,502);assert.equal((await r.json()).error,'UPSTREAM');
});
test('wrong response data is rejected',async()=>{
 const api=createQuoteApi({origin,secure:false,fetcher:async()=>Response.json({symbol:'00991A'})});const r=await api(request('abc_VALID_FUGLE_KEY_123'),'ip-5');assert.equal(r.status,502);assert.equal((await r.json()).error,'FORMAT');
});
