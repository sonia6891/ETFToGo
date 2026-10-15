/** Pure calculation and validation functions. Rates are decimal fractions, not percentages. */
export const DEFAULT_PLAN = Object.freeze({principal:100000, monthly:5000, years:10, totalReturn:0.06, distributionRate:0.04, frequency:4, reinvest:1, deductionRate:0});
const FREQ = new Set([1,2,4,12]);
export function bounded(n, name, min, max, integer=false) {
  if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max || (integer && !Number.isInteger(n))) throw new Error(`${name}須為${integer?'整數，且為':''}${min}～${max}之間的有效數值。`);
  return n;
}
export function validatePlan(p) {
  if(!p || typeof p !== 'object') throw new Error('試算格式不正確。');
  bounded(p.principal,'初始本金',0,1e12); bounded(p.monthly,'每月投入',0,1e9);
  bounded(p.years,'年數',1,50,true); bounded(p.totalReturn,'年化總報酬率',-0.9,0.5);
  bounded(p.distributionRate,'年配息比例',0,0.3); bounded(p.reinvest,'再投入比例',0,1);
  bounded(p.deductionRate,'配息扣費比例',0,0.2);
  if(!FREQ.has(p.frequency)) throw new Error('配息頻率須為月、季、半年或年。');
  return p;
}
/** A total-return wealth process with cash distributions SUBTRACTED before reinvestment. */
export function simulate(p) {
  validatePlan(p);
  const monthlyRate = Math.expm1(Math.log1p(p.totalReturn)/12);
  const interval=12/p.frequency;
  let invested=p.principal, cash=0, contributed=p.principal, distributions=0, reinvested=0, deductions=0;
  const rows=[{year:0,invested,cash,total:invested,contributed,distributions,reinvested,deductions,gain:0}];
  for(let month=1;month<=p.years*12;month++){
    invested *= 1+monthlyRate;
    if(month%interval===0){
      const gross = invested*p.distributionRate/p.frequency;
      const cost=gross*p.deductionRate;
      const net=gross-cost;
      invested -= gross;
      invested += net*p.reinvest;
      cash += net*(1-p.reinvest);
      distributions+=gross; reinvested+=net*p.reinvest; deductions+=cost;
    }
    invested+=p.monthly; contributed+=p.monthly;
    if(month%12===0) rows.push({year:month/12,invested,cash,total:invested+cash,contributed,distributions,reinvested,deductions,gain:invested+cash-contributed});
  }
  return {rows,final:rows[rows.length-1],monthlyRate};
}
export function comparePlans(p){
  return [{key:'cash',label:'全部領出',ratio:0},{key:'selected',label:'你的設定',ratio:p.reinvest},{key:'all',label:'全部再投入',ratio:1}].map(s=>({...s,...simulate({...p,reinvest:s.ratio})}));
}
export function incomeGoal(monthlyTarget, annualRate, deductionRate=0, current=0){
  bounded(monthlyTarget,'每月目標',0,1e8); bounded(annualRate,'配息率',0,.3); bounded(deductionRate,'扣費比例',0,.2); bounded(current,'目前本金',0,1e12);
  if(monthlyTarget===0)return {required:0,gap:0,netRate:annualRate*(1-deductionRate)};
  const netRate=annualRate*(1-deductionRate);
  if(netRate===0)return {required:null,gap:null,netRate};
  const required=monthlyTarget*12/netRate;
  return {required,gap:Math.max(0,required-current),netRate};
}
export function isDate(value){
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;
  const d=new Date(value+'T12:00:00Z');
  return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===value&&value>='1900-01-01'&&value<='2200-12-31';
}
function text(v,name,max=120,empty=false){if(typeof v!=='string'||(!empty&&!v.trim())||v.length>max)throw new Error(`${name}格式不正確。`);return v.trim();}
export function validateHolding(h){
  if(!h||typeof h!=='object')throw new Error('持有資料格式不正確。');
  const id=text(h.id,'記錄編號',80),code=text(h.code,'代碼',20),name=text(h.name,'名稱',120);
  if(!/^[A-Za-z0-9.-]{1,20}$/.test(code))throw new Error('代碼僅限英文字母、數字、點或短橫線。');
  bounded(h.shares,'股數',1,1e10,true);bounded(h.cost,'總成本',0,1e13);
  if(h.price!==null){bounded(h.price,'參考市價',0,1e7);if(!isDate(h.priceDate))throw new Error('填寫參考市價時，也須填有效的價格日期。');}
  if(h.priceDate!==null&&!isDate(h.priceDate))throw new Error('價格日期不正確。');
  return {id,code,name,shares:h.shares,cost:h.cost,price:h.price,priceDate:h.priceDate};
}
export function holdingSummary(holdings){
  const validated=holdings.map(validateHolding), known=validated.filter(h=>h.price!==null);
  const cost=validated.reduce((a,h)=>a+h.cost,0),knownCost=known.reduce((a,h)=>a+h.cost,0);
  const value=known.length?known.reduce((a,h)=>a+h.shares*h.price,0):null;
  return {count:validated.length,knownCount:known.length,cost,knownCost,value,gain:value===null?null:value-knownCost,complete:known.length===validated.length&&validated.length>0};
}
export function validateDividend(d){
  if(!d||typeof d!=='object')throw new Error('配息記錄格式不正確。');
  const id=text(d.id,'記錄編號',80),code=text(d.code,'代碼',20),name=text(d.name,'名稱',120);
  if(!/^[A-Za-z0-9.-]{1,20}$/.test(code))throw new Error('代碼格式不正確。');
  if(!isDate(d.paymentDate))throw new Error('請填有效的入帳日。');
  if(d.exDate!==null&&!isDate(d.exDate))throw new Error('除息日不正確。');
  if(d.exDate&&d.paymentDate<d.exDate)throw new Error('入帳日不可早於除息日。');
  bounded(d.eligibleShares,'本次具配息資格股數',1,1e10,true);bounded(d.perShare,'每股配息',0,1e5);
  const gross=d.eligibleShares*d.perShare;bounded(d.deductions,'本次扣費',0,gross);
  if(!['planned','announced','received'].includes(d.status))throw new Error('配息狀態不正確。');
  if(d.status==='received'&&d.actualReceived===null)throw new Error('已入帳記錄須填實際入帳金額。');
  if(d.actualReceived!==null)bounded(d.actualReceived,'實際入帳金額',0,1e15);
  const sourceUrl=text(d.sourceUrl||'','來源連結',2048,true);
  if(sourceUrl){let u;try{u=new URL(sourceUrl);}catch{throw new Error('來源連結格式不正確。');}if(!['http:','https:'].includes(u.protocol)||u.username||u.password)throw new Error('來源連結須使用http或https，且不可含帳密。');}
  return {id,code,name,paymentDate:d.paymentDate,exDate:d.exDate,eligibleShares:d.eligibleShares,perShare:d.perShare,deductions:d.deductions,status:d.status,actualReceived:d.actualReceived,sourceUrl};
}
export function dividendAmount(d){const v=validateDividend(d);return v.status==='received'?v.actualReceived:v.eligibleShares*v.perShare-v.deductions;}
export function monthlyCashflow(dividends,year){
  bounded(year,'年份',1900,2200,true);
  const months=Array.from({length:12},(_,i)=>({month:i+1,received:0,announced:0,planned:0,count:0}));
  for(const raw of dividends){const d=validateDividend(raw);if(Number(d.paymentDate.slice(0,4))!==year)continue;const m=months[Number(d.paymentDate.slice(5,7))-1];m[d.status]+=dividendAmount(d);m.count++;}
  return months;
}
export function emptyStore(){return {version:2,holdings:[],dividends:[],plan:{...DEFAULT_PLAN}};}
export function validateBackup(raw){
  if(!raw||typeof raw!=='object'||raw.version!==2||!Array.isArray(raw.holdings)||!Array.isArray(raw.dividends))throw new Error('不是ETF工具V2備份格式。');
  if(raw.holdings.length>10000||raw.dividends.length>50000)throw new Error('備份記錄數超出上限。');
  const holdings=raw.holdings.map(validateHolding),dividends=raw.dividends.map(validateDividend);
  if(new Set(holdings.map(h=>h.id)).size!==holdings.length||new Set(dividends.map(d=>d.id)).size!==dividends.length)throw new Error('備份內有重複的記錄編號。');
  const p=validatePlan(raw.plan||{...DEFAULT_PLAN});
  const plan=Object.fromEntries(Object.keys(DEFAULT_PLAN).map(k=>[k,p[k]]));
  return {version:2,holdings,dividends,plan};
}
export function parseBackup(value){if(typeof value!=='string'||value.length>5_000_000)throw new Error('備份檔太大或格式不正確。');let raw;try{raw=JSON.parse(value);}catch{throw new Error('JSON格式損毀；原有資料未更動。');}return validateBackup(raw);}
export const STORE_KEY='etf:planning-tools:v2';
export function readStorage(storage){
  try{const raw=storage.getItem(STORE_KEY);return {data:raw===null?emptyStore():parseBackup(raw),warning:'',blocked:false};}
  catch(e){return {data:emptyStore(),warning:'本機資料無法讀取；既有資料未覆寫。請先備份，或在下次儲存時確認建立新資料。',blocked:true};}
}
export function writeStorage(storage,data){const checked=validateBackup(data);storage.setItem(STORE_KEY,JSON.stringify(checked));return checked;}
export function csv(rows){return '\ufeff'+rows.map(row=>row.map(value=>{let s=String(value??'');if(typeof value==='string'&&/^[=+\-@\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}).join(',')).join('\r\n');}
export function escapeHTML(v){return String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');}
