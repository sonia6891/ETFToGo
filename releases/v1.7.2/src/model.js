import {holdingSummary,monthlyCashflow,validateBackup,dividendAmount} from './etf-tools/finance.js';
export const VERSION='1.7.1';
export const CATEGORIES=[{id:'market-cap',label:'市值型',hint:'以大盤、市值策略為主'},{id:'high-dividend',label:'高股息',hint:'以股息策略為主'},{id:'thematic',label:'產業主題',hint:'聚焦特定產業或主題'},{id:'other',label:'其他策略',hint:'其他指數與因子策略'},{id:'active',label:'主動型',hint:'經理人主動管理'},{id:'pending',label:'待分類',hint:'策略仍待覆核'}];
export const categoryLabel=id=>CATEGORIES.find(x=>x.id===id)?.label||'未分類';
export function taipeiDate(now=new Date()){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Taipei',year:'numeric',month:'2-digit',day:'2-digit'}).format(now);}
export function validCodes(raw){return Array.isArray(raw)?[...new Set(raw.filter(x=>typeof x==='string'&&/^[0-9]{4,6}[A-Z]?$/.test(x)))].slice(0,1000):[];}
export function catalogData(raw){
 if(!raw||raw.ok!==true||!['twse-domestic-equity','twse-listed'].includes(raw.scope)||!Array.isArray(raw.records)||raw.records.length<1||raw.records.length>1000||!/^\d{4}-\d{2}-\d{2}$/.test(raw.sourceDate))throw Error('名單格式異常，保留原有資料。');
 const seen=new Set();
 const records=raw.records.map(x=>{
  if(!x||validCodes([x.code]).length!==1||seen.has(x.code)||typeof x.name!=='string'||x.name.length>120||!['active','passive'].includes(x.management))throw Error('ETF 名單未通過驗證。');seen.add(x.code);
  return {...x,category:CATEGORIES.some(c=>c.id===x.category)?x.category:'pending',tags:Array.isArray(x.tags)?x.tags.filter(t=>typeof t==='string').slice(0,5):[]};
 });return {...raw,records};
}
export function portfolioSummary(store,records=[],date=taipeiDate()){
 const data=validateBackup(store),s=holdingSummary(data.holdings),year=Number(date.slice(0,4));
 const months=monthlyCashflow(data.dividends,year),current=months[Number(date.slice(5,7))-1];
 const allocation={};for(const h of data.holdings){const c=records.find(e=>e.code===h.code)?.category||'unclassified';allocation[c]=(allocation[c]||0)+h.cost;}
 return {...s,months,current,yearReceived:months.reduce((a,m)=>a+m.received,0),allocation,upcoming:data.dividends.filter(d=>d.status!=='received'&&d.paymentDate>=date).sort((a,b)=>a.paymentDate.localeCompare(b.paymentDate)),overdue:data.dividends.filter(d=>d.status!=='received'&&d.paymentDate<date).sort((a,b)=>b.paymentDate.localeCompare(a.paymentDate))};
}
export function calendarCells(year,month){
 if(!Number.isInteger(year)||year<1900||year>2200||!Number.isInteger(month)||month<1||month>12)throw Error('月份不正確。');
 const first=new Date(Date.UTC(year,month-1,1)).getUTCDay(),days=new Date(Date.UTC(year,month,0)).getUTCDate();
 return Array.from({length:Math.ceil((first+days)/7)*7},(_,i)=>i<first||i>=first+days?null:`${year}-${String(month).padStart(2,'0')}-${String(i-first+1).padStart(2,'0')}`);
}
export function holdingFromForm(value,id){
 const factor=value.unit==='lots'?1000:1,shares=Number(value.shares)*factor;
 if(!Number.isSafeInteger(shares)||shares<1)throw Error('持有數量換算後須為有效的整數股數。');
 return {id,code:String(value.code).trim().toUpperCase(),name:String(value.name).trim(),shares,cost:Number(value.cost),price:value.price===''?null:Number(value.price),priceDate:value.price===''?null:(value.priceDate||null)};
}
export {dividendAmount};
