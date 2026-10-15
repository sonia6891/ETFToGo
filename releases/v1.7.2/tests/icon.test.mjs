import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const root=new URL('../',import.meta.url);
const load=p=>readFileSync(new URL(p,root));
const text=p=>load(p).toString('utf8');
test('Apple touch icon explicitly references a unique 180px PNG',()=>{
  const html=text('dist/index.html');
  assert.match(html, /rel="apple-touch-icon" href="https:\/\/etf-independent-app-production\.up\.railway\.app\/apple-touch-icon-v172\.png"/);
  assert.match(html, /rel="icon" type="image\/png" href="https:\/\/etf-independent-app-production\.up\.railway\.app\/icon-192-v172\.png"/);
});
test('App header also uses updated pocket image, not the old mark',()=>{assert.match(text('dist/index.html'),/class="brandmark"[^>]*><img src="\/icon-192-v171\.png"/);});
test('PWA manifest uses cache busting names without resetting the app ID',()=>{
  const manifest=JSON.parse(text('dist/manifest.webmanifest'));
  assert.equal(manifest.id,'./');
  assert.equal(manifest.name,'ETF 袋著走');
  assert.deepEqual(manifest.icons.map(x=>x.src),['https://etf-independent-app-production.up.railway.app/icon-192-v172.png','https://etf-independent-app-production.up.railway.app/icon-512-v172.png']);
});
test('New icon files have correct PNG width and height',()=>{
  for(const [path,size] of [['public/icon-192-v171.png',192],['public/icon-512-v171.png',512],['public/apple-touch-icon-v171.png',180],['public/apple-touch-icon.png',180]]){
    const b=load(path);
    assert.equal(b.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
    assert.equal(b.readUInt32BE(16),size);
    assert.equal(b.readUInt32BE(20),size);
  }
});
test('Service worker declares the current UI release cache',()=>{
 const sw=text('dist/sw.js');
 assert.match(sw,/etf-togo-1\.7\.2-icon/);
 assert.ok(sw.includes('if(/\\.(png|ico|webmanifest)$/.test(u.pathname))return;'));
 assert.ok(!sw.includes('cache.clear'));
 assert.ok(!sw.includes('localStorage'));
});
