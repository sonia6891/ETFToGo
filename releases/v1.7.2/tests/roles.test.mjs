import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {normalizeReference} from '../server/reference-service.js';
import {classifyRole} from '../server/role-classifier.js';
import {catalogData} from '../src/model.js';
const rows=JSON.parse(readFileSync(new URL('./fixtures/twse-2026-10-14.json',import.meta.url)));
test('all listed codes survive normalization and frontend schema',()=>{
 const c=normalizeReference(rows,Date.parse('2026-10-15T00:00:00Z'));
 assert.equal(c.scope,'twse-listed');assert.equal(c.records.length,272);
 assert.equal(catalogData({...c,ok:true}).records.length,272);
 assert.equal(new Set(c.records.map(x=>x.code)).size,272);
 assert.ok(c.records.every(x=>x.market==='TWSE'&&x.roleAssessment.historyVerified===false));
 assert.ok(c.records.some(x=>x.fundType.includes('國外')));
});
test('risk structure takes priority over dividend name; no guaranteed profits',()=>{
 assert.equal(classifyRole({code:'00631L',name:'台灣50正2高股息'}).role,'slotMachine');
 assert.equal(classifyRole({code:'00878',name:'高股息'}).status,'候選・待核驗');
 assert.equal(classifyRole({code:'0050',name:'Taiwan 台灣50'}).role,'piggyBank');
 assert.equal(classifyRole({code:'00991A',name:'主動型'}).role,null);
});
