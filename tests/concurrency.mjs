import {chromium} from 'playwright';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {balance} from '../src/domain.js';
const b=await chromium.launch({channel:'chrome',headless:true}),c=await b.newContext();
try{const p=await c.newPage(),q=await c.newPage();for(const page of[p,q]){await page.goto('http://127.0.0.1:4500/');await page.locator('.workspace').waitFor();}
const state=()=>p.evaluate(()=>new Promise(resolve=>{const r=indexedDB.open('aksa-stockflow-v1',1);r.onsuccess=()=>{const db=r.result,q=db.transaction('workspace').objectStore('workspace').get('state');q.onsuccess=()=>{resolve(q.result);db.close();};};}));
const before=await state(),product=before.products.find(p=>p.sku==='AM-FD-003'),initial=balance(before,product.id,'loc-warehouse'),documents=before.receipts.length;
for(const[page,quantity]of [[p,5],[q,7]]){await page.getByRole('button',{name:'Stock in',exact:true}).last().click();const d=page.getByRole('dialog');await d.getByLabel('Destination location *',{exact:true}).selectOption('loc-warehouse');await d.getByRole('textbox',{name:'Scan barcode, enter SKU or find a product…',exact:true}).fill(product.sku);await d.getByRole('textbox',{name:'Scan barcode, enter SKU or find a product…',exact:true}).press('Enter');await d.getByLabel(`Quantity for ${product.sku}`,{exact:true}).fill(String(quantity));await d.getByRole('button',{name:'Review document',exact:true}).click();}
await Promise.all([p,q].map(page=>page.getByRole('dialog').getByRole('button',{name:'Confirm & record',exact:true}).click()));await Promise.all([p,q].map(page=>page.getByRole('dialog').waitFor({state:'hidden'})));
const after=await state();assert.equal(balance(after,product.id,'loc-warehouse'),initial+12);assert.equal(after.receipts.length,documents+2);assert.equal(new Set(after.receipts.map(r=>r.number)).size,after.receipts.length);
const result={passed:1,checks:['Two simultaneous browser-tab receipts preserve both quantities, two documents and unique sequence numbers'],initial,final:balance(after,product.id,'loc-warehouse')};await writeFile('test-artifacts/concurrency-results.json',JSON.stringify(result,null,2));console.log('PASS',result.checks[0]);
}finally{await b.close();}
