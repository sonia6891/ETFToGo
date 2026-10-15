from pathlib import Path
p=Path(__file__).resolve().parents[1]/'src/app.js'
s=p.read_text()
marker='function compare(){'
assert s.count(marker)==1
method='''function compareOverlapPanel(){
 const codes=comparison.slice(0,3),available=codes.filter(code=>constituentData.has(code)),missing=codes.filter(code=>!constituentData.has(code));
 if(codes.length<2)return '';
 const holdings=new Map();
 for(const code of available){for(const item of constituentData.get(code).components){let x=holdings.get(item.symbol);if(!x){x={name:item.name,codes:[],weights:[]};holdings.set(item.symbol,x);}x.codes.push(code);x.weights.push(item.weight);}}
 const common=[...holdings.entries()].filter(([symbol,row])=>row.codes.length>1).sort((a,b)=>Math.min(...b[1].weights)-Math.min(...a[1].weights));
 const hint=missing.length?`<div class="info-box">目前缺少 ${missing.map(esc).join('、')} 的成分股資料，只能對已取得資料的 ETF 進行部分比較。未取得完整資料前，不會顯示「零重疊」或估算全部風險。</div>`:'';
 return `<section class="card"><div class="cardhead"><h2>持股重疊透視</h2><span class="feature-badge">ETF 實際持股</span></div><p class="small" style="margin:12px 0">同一家股票是否同時出現在不同 ETF？依成分股公告日期比較，非盤中即時持股。</p>${hint}${common.length?`<div class="constituent-list">${common.slice(0,20).map(([symbol,row])=>`<div class="constituent-row"><div><b>${esc(row.name)}</b><small>${esc(symbol)} · ${row.codes.map((c,i)=>esc(c)+' '+row.weights[i].toFixed(2)+'%').join('／')}</small></div><strong>${row.codes.length} 檔重疊</strong></div>`).join('')}</div>`:missing.length?'':`<div class="info-box">可用成分股中未發現相同股票；仍須以各檔公告完整性為準。</div>`}<div class="inline-actions">${codes.map(c=>`<a href="#etf/${esc(c)}/components" class="button">${esc(c)} 成分股</a>`).join('')}</div></section>`;
}
'''
s=s.replace(marker,method+marker)
old='${sourceNote()}`;}\nfunction favoritesPage()'
assert s.count(old)==1
s=s.replace(old,'${compareOverlapPanel()}${sourceNote()}`;}\nfunction favoritesPage()')
# ETF details support deep links for component tab without a preceding comparison visit.
old="const [view='home',arg='']=location.hash.replace(/^#\\/?/,'').split('/');"
assert s.count(old)==1
s=s.replace(old,"const [view='home',arg='',subview='']=location.hash.replace(/^#\\/?/,'').split('/');if(view==='etf'&&['overview','components','dividend','info'].includes(subview))detailTab=subview;")
p.write_text(s)
print('Updated',p, 'bytes',p.stat().st_size)
