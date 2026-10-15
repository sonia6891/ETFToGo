const CACHE='etf-togo-1.7.2-icon';
const BASE=new URL('/',self.location.href);
const FILES=['index.html','brand-mark.svg'].map(p=>new URL(p,BASE).pathname);
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>(k.startsWith('etf-independent-')||k.startsWith('etf-togo-'))&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(u.origin!==self.location.origin||e.request.method!=='GET'||u.pathname.startsWith('/api/')||u.pathname==='/health')return;
// Home-screen icons and install metadata go straight to the network. iOS owns its separate icon cache.
if(/\.(png|ico|webmanifest)$/.test(u.pathname))return;
if(e.request.mode==='navigate'){e.respondWith(fetch(e.request).then(r=>{if(r.ok){const copy=r.clone();e.waitUntil(caches.open(CACHE).then(c=>c.put('/index.html',copy)));}return r;}).catch(()=>caches.match('/index.html')));return;}
if(FILES.includes(u.pathname))e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)));});
