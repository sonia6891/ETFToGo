from playwright.sync_api import sync_playwright
from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
CAT={'ok':True,'version':1,'scope':'twse-domestic-equity','sourceDate':'2026-10-13','records':[{'code':c,'name':n,'category':cat,'management':'active' if cat=='active' else 'passive','tags':[],'sourceDate':'2026-10-13','listingDate':'2025-01-01','classificationBasis':'測試分類，非官方逐檔審核','index':None} for c,n,cat in [('0050','元大台灣50','market-cap'),('00878','國泰永續高股息','high-dividend'),('00991A','主動復華未來50','active'),('0056','元大高股息','high-dividend')]]}
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 page=b.new_page(viewport={'width':390,'height':844},device_scale_factor=2)
 page.evaluate('''cat=>{window.__testStore=new Map();Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>window.__testStore.get(k)??null,setItem:(k,v)=>window.__testStore.set(k,String(v)),removeItem:k=>window.__testStore.delete(k)}});window.fetch=async input=>{const path=String(input);if(path.includes('/api/catalog'))return Response.json(cat);if(path.includes('/api/market/status'))return Response.json({connected:false,clock:{label:'測試環境',pollSeconds:300}});return Response.json({error:'TEST_NO_NETWORK'},{status:503});};}''',CAT)
 page.set_content((r/'dist/index.html').read_text(),wait_until='load')
 svg=(r/'public/brand-mark.svg').read_text()
 page.locator('.brandmark img').evaluate('(el,svg)=>{el.src="data:image/svg+xml;charset=utf-8,"+encodeURIComponent(svg)}',svg)
 page.wait_for_timeout(280)
 page.screenshot(path=str(r/'docs/ETFToGo_home_preview.png'))
 page.evaluate("location.hash='#list'");page.wait_for_timeout(220)
 page.screenshot(path=str(r/'docs/ETFToGo_list_preview.png'))
 page.evaluate("location.hash='#etf/0050'");page.wait_for_timeout(210)
 page.get_by_role('button',name='成分股').click();page.wait_for_timeout(250)
 page.screenshot(path=str(r/'docs/ETFToGo_components_preview.png'))
 page.evaluate("location.hash='#brokers'");page.wait_for_timeout(250)
 page.screenshot(path=str(r/'docs/ETFToGo_brokers_preview.png'))
 print('Screenshots created. errors?',page.locator('html').count())
 b.close()
