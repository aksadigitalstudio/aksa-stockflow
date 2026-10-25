export const CONFIG=Object.freeze({
  appName:'AKSA StockFlow',businessName:'Aruna Mart',businessProfile:'Retail store · main shop & backroom warehouse',
  locations:[{id:'loc-store',name:'Main Store',code:'STR',type:'Retail',active:true,description:'Customer-facing shop floor'},{id:'loc-warehouse',name:'Warehouse',code:'WH',type:'Warehouse',active:true,description:'Backroom storage & replenishment'}],
  units:[{name:'Piece',discrete:true},{name:'Pack',discrete:true},{name:'Box',discrete:true},{name:'Bottle',discrete:true},{name:'Kilogram',discrete:false},{name:'Meter',discrete:false}],
  currency:'IDR',locale:'en-US',timeZone:'Asia/Jakarta',allowNegative:false,
  largeVarianceQty:10,largeVariancePercent:10,
  countPolicy:'Location snapshots · optional blind counts · review before adjustment · supervisor approval for large variances',
  theme:{charcoal:'#202823',paper:'#f7f8f4',emerald:'#2a694f',blue:'#426ca2'},
  storageKey:'aksa-stockflow-v1',schemaVersion:1,
});
export const ROLES=['OWNER','ADMIN','WAREHOUSE STAFF','STOCK COUNTER','SUPERVISOR','VIEWER'];
export const DEMO_USERS=[{id:'u-owner',name:'Alya Pratama',role:'OWNER'},{id:'u-admin',name:'Rafi Mahendra',role:'ADMIN'},{id:'u-staff',name:'Dimas Saputra',role:'WAREHOUSE STAFF'},{id:'u-counter',name:'Nadia Putri',role:'STOCK COUNTER'},{id:'u-supervisor',name:'Maya Santoso',role:'SUPERVISOR'},{id:'u-viewer',name:'Guest observer',role:'VIEWER'}];
