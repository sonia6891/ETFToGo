import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const read=p=>readFile(resolve(root,p),'utf8');
function strip(s){return s.replace(/^import .*?;\n/gm,'').replace(/\bexport (?=(?:const|function|class|async function))/g,'').replace(/^export \{[^}]+\};?\s*$/gm,'');}
function wrap(s,imports,exports){return `(()=>{\n${imports}\n${strip(s)}\nreturn {${exports}};\n})()`;}
const finance=await read('src/etf-tools/finance.js');const names=[...finance.matchAll(/export (?:function|const) (\w+)/g)].map(m=>m[1]);
const theme=(await read('src/etf-tools/theme.js')).replace('export const STYLE','const STYLE').replace(/`;\s*$/,`${await read('src/tool-overrides.css')}\n\x60;`);
const financeBindings=`const {${names.join(',')}}=Finance;`;
const element=strip(await read('src/etf-tools/element.js')).replace('const esc=escapeHTML;','const esc=escapeHTML;');
const modelExports='VERSION,CATEGORIES,categoryLabel,catalogData,validCodes,taipeiDate,portfolioSummary,calendarCells,holdingFromForm,dividendAmount';
const js=`const Finance=${wrap(finance,'',names.join(','))};\n(()=>{${financeBindings}\n${theme}\n${element}\n})();\nconst Model=${wrap(await read('src/model.js'),financeBindings,modelExports)};\nconst Icons=${wrap(await read('src/icons.js'),'','icon')};\nconst Quotes=${wrap(await read('src/quotes.js'),'const {escapeHTML:esc}=Finance;','createQuotes')};\n(()=>{const {escapeHTML:esc,emptyStore,readStorage,validateHolding,validateBackup,parseBackup,STORE_KEY}=Finance;const {${modelExports}}=Model;const {icon}=Icons;const {createQuotes}=Quotes;\n${strip(await read('src/app.js'))}\n})();`;
const html=(await read('src/index.html')).replace('/* APP_CSS */',await read('src/app.css')).replace('/* APP_SCRIPT */',js.replaceAll('</script','<\\/script'));
await mkdir(resolve(root,'dist'),{recursive:true});await writeFile(resolve(root,'dist/index.html'),html);await writeFile(resolve(root,'dist/app.check.mjs'),js);
for(const file of ['manifest-v172.webmanifest','icon-192-v172.png','icon-512-v172.png','apple-touch-icon-v172.png','icon-192-v171.png','icon-512-v171.png','apple-touch-icon-v171.png','install-pocket.html','icon-192-v161.png','icon-512-v161.png','apple-touch-icon-v161.png','apple-touch-icon-precomposed.png','favicon.ico','icon-192.png','icon-512.png','icon-192-v141.png','icon-192-v150.png','icon-512-v141.png','icon-512-v150.png','apple-touch-icon-v141.png','apple-touch-icon-v150.png','apple-touch-icon.png','brand-mark.svg','manifest.webmanifest','sw.js'])await copyFile(resolve(root,'public',file),resolve(root,'dist',file));
console.log(`Built ETF 1.7.1: ${Buffer.byteLength(html)} bytes. No external JS/CSS dependency.`);
