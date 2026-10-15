import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {startHost} from '../server/host.js';

test('iOS icon responses include bytes for revalidation, correct HEAD size, and a fresh app route',async()=>{
 const oldBun=globalThis.Bun,oldFetch=globalThis.fetch;
 let handler;
 const server={port:3000,requestIP:()=>({address:'127.0.0.1'})};
 globalThis.Bun={env:{},CryptoHasher:class{constructor(){this.h=createHash('sha256');}update(b){this.h.update(b);return this;}digest(t){return this.h.digest(t);}},serve(options){handler=options.fetch;return server;}};
 globalThis.fetch=async(input)=>{
  const url=String(input);
  if(url==='https://reference.test/catalog')return Response.json({ok:true,version:1,scope:'twse-listed',records:[{symbol:'0050'}],sourceDate:'2026-10-14'});
  return handler(new Request(url),server);
 };
 try{
  const icon=readFileSync(new URL('../dist/apple-touch-icon-v172.png',import.meta.url));
  const source={'index.html':'<!doctype html><title>ETF 袋著走</title>','apple-touch-icon-v172.png':icon.toString('base64')};
  await startHost({source,version:'1.7.2',htmlSha256:'test',origin:'https://app.test',referenceEndpoint:'https://reference.test/catalog'});
  const first=await handler(new Request('https://app.test/apple-touch-icon-v172.png'),server);
  const again=await handler(new Request('https://app.test/apple-touch-icon-v172.png',{headers:{'If-None-Match':first.headers.get('etag')}}),server);
  assert.equal(again.status,200);
  assert.equal(again.headers.get('content-type'),'image/png');
  assert.match(again.headers.get('cache-control'),/public, max-age=31536000, immutable/);
  assert.equal(again.headers.has('content-security-policy'),false);
  assert.equal(again.headers.get('x-content-type-options'),'nosniff');
  assert.deepEqual(Buffer.from(await again.arrayBuffer()),icon);
  const head=await handler(new Request('https://app.test/apple-touch-icon-v172.png',{method:'HEAD'}),server);
  assert.equal(Number(head.headers.get('content-length')),icon.length);
  assert.equal((await head.arrayBuffer()).byteLength,0);
  const app=await handler(new Request('https://app.test/app-v172.html'),server);
  assert.equal(app.status,200);
  assert.match(app.headers.get('content-security-policy'),/frame-ancestors 'none'/);
  assert.equal(await app.text(),source['index.html']);
 }finally{globalThis.Bun=oldBun;globalThis.fetch=oldFetch;}
});
