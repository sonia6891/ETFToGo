from pathlib import Path
p=Path(__file__).resolve().parents[1]
app=p/'src/app.js'
s=app.read_text('utf-8')
old="<section class=\"greeting\"><div><h1>你的 ETF，今天也整理好了。</h1><p>持有、配息、成分股，想看什麼一點就到。</p></div></section>"
new="<section class=\"greeting\"><div><h1>你的 ETF，都在這裡。</h1><p>每筆持有、股息與成分股資訊，隨手就能查看。</p></div></section>"
assert s.count(old)==1,s.count(old)
s=s.replace(old,new)
old="document.documentElement.classList.toggle('privacy-hidden',hideMoney);if(storeBlocked||tools.blocked)"
new="document.documentElement.classList.toggle('privacy-hidden',hideMoney);document.body.classList.toggle('home-view',view==='home');if(storeBlocked||tools.blocked)"
assert s.count(old)==1
s=s.replace(old,new)
# Keep every action bound to current business logic. No dashboard mock image used.
app.write_text(s,'utf-8')
css=p/'src/app.css'
s=css.read_text('utf-8')
s+='''

/* 1.5.0 actual application UI — compact blue/white design inspired by the approved concept.
   Real holdings and quote values only; no stock charts or demo numbers fabricated. */
:root{--bg:#f2f7ff;--card:#fff;--soft:#eaf3ff;--line:#e2ebf8;--accent:#176df3;--shadow:0 8px 28px rgba(25,73,154,.055)}
:root.dark{--bg:#0d1628;--card:#162238;--soft:#203551;--line:#2b3b57;--accent:#8ab6ff;--shadow:none}
body{background:var(--bg)}
.brandmark{width:36px;height:36px;border-radius:10px;overflow:hidden;box-shadow:none}
.brandmark img{width:36px;height:36px;filter:none;object-fit:cover;border-radius:9px}
.summary-card{background:linear-gradient(154deg,#fafdff 5%,#eaf3ff 100%);border:1px solid #dce9ff}
.dark .summary-card{background:linear-gradient(155deg,#1a2c48,#162238);border-color:var(--line)}
.summary-card:after{opacity:.42}
.summary-card .amount{font-weight:800}
.card,.panel{box-shadow:var(--shadow)}
.quick .quick-icon{border-radius:50%}
.home-view .greeting h1{color:var(--ink)}
@media(max-width:700px){
  .frame{padding:12px 16px 105px;max-width:480px}
  .topbar{min-height:44px;margin-bottom:1px;gap:8px}
  .top-actions{gap:0}
  .topbar .brand{gap:0}
  .topbar .brandmark{display:none} /* the desktop/iPhone home-screen icon is a separate PWA asset */
  .topbar .brandname{font-size:14px;font-weight:800;letter-spacing:0}
  .topbar .brand small{display:none}
  .topbar .iconbtn{width:40px;height:40px;min-width:40px;min-height:40px}
  .home-view .topbar .brandname{font-size:14px}
  #quote-status{font-size:11px;padding:4px 9px;min-height:25px!important}
  .frame>div:has(>#quote-status){margin:0 0 8px!important}
  .greeting{margin:2px 0 14px;align-items:flex-start}
  .greeting h1{font-size:18px;font-weight:800;line-height:1.3;letter-spacing:-.025em}
  .greeting p{font-size:11px;margin-top:3px;line-height:1.4}
  .dashboard{display:block}
  .card,.panel{border-radius:17px;padding:15px;margin-bottom:13px}
  .summary-card{padding:17px 16px 15px;border-radius:18px}
  .summary-card .cardhead{margin-bottom:9px}
  .summary-card .cardhead h3{font-size:14px;color:var(--accent)}
  .summary-card .cardhead .iconbtn{min-height:36px;min-width:36px}
  .label{font-size:10px;letter-spacing:.012em}
  .amount{font-size:34px;line-height:1.12;margin:5px 0 0;letter-spacing:-.025em}
  .gain{font-size:12px;line-height:1.35;margin-top:5px}
  .metrics{gap:7px;margin-top:15px}
  .mini{padding:10px 8px;border-radius:12px}
  .mini span{font-size:9px;line-height:1.3;display:block}
  .mini b{font-size:15px;margin-top:5px;line-height:1.25}
  .mini b span{display:inline;font-size:10px}
  .fineprint{font-size:10px;line-height:1.48;margin-top:11px}
  .quick-grid{margin:17px 0 19px;gap:5px}
  .quick{font-size:11px;gap:7px;min-height:76px;padding:1px 0}
  .quick .quick-icon{width:47px;height:47px;border-radius:50%;box-shadow:0 5px 13px rgba(0,61,153,.09)}
  .quick .icon{width:21px;height:21px}
  .onboarding{display:block;padding:15px 16px}
  .onboarding .illustration{display:none}
  .onboarding h3{font-size:14px}
  .onboarding p{font-size:11px;line-height:1.5;margin-top:5px}
  .onboarding .button{min-height:42px;padding:8px 15px;margin-top:10px}
  .section-head{margin:15px 0 10px}
  .section-head h2{font-size:16px}
  .section-head a{font-size:11px;min-height:29px}
  .etf-card{padding:12px 10px;gap:6px;grid-template-columns:minmax(0,1fr) minmax(70px,auto) 32px}
  .etf-card .etf-name{font-size:12px}
  .etf-card .code{font-size:13px}
  .etf-card .q-price{font-size:14px}
  .etf-card .q-caption{font-size:10px}
  .list-panel{border-radius:15px}
  .bottom-nav{box-shadow:0 -5px 20px rgba(23,65,123,.045)}
  .bottom-nav a{min-height:60px;font-size:10px;gap:3px}
  .bottom-nav .icon{width:20px;height:20px}
  .bottom-nav a.current:before{height:2px}
  .page-title{margin:10px 0 12px}
  .page-title h1{font-size:21px}
  .searchbox{margin-top:5px}
  .details-grid{gap:7px}
  .detail-field{padding:11px}
  .calendar-grid{gap:3px 1px}
  .calendar-grid .day{min-height:38px}
  .modal{padding:19px 17px;border-radius:22px}
}
@media(max-width:360px){
  .frame{padding:10px 12px 105px}
  .mini{padding:9px 5px}
  .mini b{font-size:14px}
  .quick{font-size:10px}
  .greeting h1{font-size:17px}
}
'''
css.write_text(s,'utf-8')
html=p/'src/index.html'
s=html.read_text('utf-8')
s=s.replace('<meta name="apple-mobile-web-app-title" content="ETF 袋著走">','<meta name="apple-mobile-web-app-title" content="ETF 袋著走"><meta name="apple-mobile-web-app-status-bar-style" content="default">')
s=s.replace('<link rel="manifest" href="./manifest.webmanifest?v=141">','<link rel="manifest" href="./manifest.webmanifest?v=150">')
s=s.replace('href="./icon-192-v141.png"','href="./icon-192-v150.png"')
s=s.replace('href="./apple-touch-icon-v141.png"','href="./apple-touch-icon-v150.png"')
s=s.replace('<span class="brandmark" aria-hidden="true"><img src="./icon-192-v141.png" alt="" width="46" height="46"></span>','<span class="brandmark" aria-hidden="true"><img src="./icon-192-v150.png" alt="" width="40" height="40"></span>')
html.write_text(s,'utf-8')
from shutil import copyfile
for filename in ('icon-192','icon-512','apple-touch-icon'):
 copyfile(p/'public'/f'{filename}-v141.png',p/'public'/f'{filename}-v150.png')
manifest=p/'public/manifest.webmanifest'
s=manifest.read_text('utf-8').replace('v141.png','v150.png').replace('"start_url":"./#home"','"start_url":"./?release=150#home"')
manifest.write_text(s,'utf-8')
sw=p/'public/sw.js'
s=sw.read_text('utf-8').replace('1.4.1','1.5.0').replace('v141','v150')
sw.write_text(s,'utf-8')
build=p/'scripts/build.mjs'
s=build.read_text('utf-8').replace("'icon-192-v141.png'","'icon-192-v141.png','icon-192-v150.png'").replace("'icon-512-v141.png'","'icon-512-v141.png','icon-512-v150.png'").replace("'apple-touch-icon-v141.png'","'apple-touch-icon-v141.png','apple-touch-icon-v150.png'").replace('Built ETF 1.4.1','Built ETF 1.5.0')
build.write_text(s,'utf-8')
package=p/'package.json'
s=package.read_text('utf-8').replace('"version": "1.4.1"','"version": "1.5.0"')
package.write_text(s,'utf-8')
print('Created 1.5 visual refinement; no fabricated financial data added')
