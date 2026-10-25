import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import {executeCommand,restrictView,validateState} from '../_shared/domain.js';
const url=Deno.env.get('SUPABASE_URL')!,serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
const allowed=(Deno.env.get('STOCKFLOW_ALLOWED_ORIGINS')||'http://127.0.0.1:4500').split(',').map(v=>v.trim());
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'',headers={'Access-Control-Allow-Origin':allowed.includes(origin)?origin:allowed[0],'Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin','Content-Type':'application/json'};
 const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(origin&&!allowed.includes(origin))return json({error:'This origin is not authorized.'},403);
 if(req.method!=='POST')return json({error:'POST required.'},405);
 try{
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');
  const{data:userData,error:authError}=await admin.auth.getUser(token);if(authError||!userData.user)return json({error:'Sign in with an authorized staff account.'},401);
  const{data:actor,error:profileError}=await admin.rpc('stockflow_profile',{p_user:userData.user.id});if(profileError||!actor)return json({error:'An active staff profile is required. Contact your workspace owner.'},403);
  const raw=await req.text();if(raw.length>2_000_000)return json({error:'Request is too large.'},413);const body=JSON.parse(raw);
  if(!['read','command'].includes(body.action))return json({error:'Unsupported action.'},400);
  if(body.action==='command'&&(!body.command||JSON.stringify(body.command).length>1_500_000))return json({error:'Invalid inventory command.'},400);
  let uploaded:string|null=null;
  for(let attempt=0;attempt<4;attempt++){
   const{data:current,error:readError}=await admin.rpc('stockflow_read');if(readError)throw readError;
   // SQL ledger ordering metadata is private and not a business field.
   for(const m of current.movements)delete m._order;
   validateState(current);let next=current;
   if(body.action==='command'){
    // Identity, role, balances and snapshot quantities always come from server data, never the caller.
    next=executeCommand(current,body.command,actor);
    if(next!==current){
     const p=body.command.type==='product.save'?next.products.find((p:any)=>p.id===next.lastResult):null;
     if(p?.image?.startsWith('data:image/')){
      if(uploaded)await admin.storage.from('stockflow-products').remove([uploaded]);
      const match=p.image.match(/^data:(image\/(?:webp|png|jpeg));base64,(.+)$/),bytes=Uint8Array.from(atob(match[2]),c=>c.charCodeAt(0));
      uploaded=`products/${p.id}/${crypto.randomUUID()}.${match[1].split('/')[1]}`;
      const{error}=await admin.storage.from('stockflow-products').upload(uploaded,bytes,{contentType:match[1],upsert:false});if(error)throw error;p.image='storage:'+uploaded;
     }
     const{error:commitError}=await admin.rpc('stockflow_commit',{p_state:next,p_expected:current.revision});
     if(commitError){if(uploaded){await admin.storage.from('stockflow-products').remove([uploaded]);uploaded=null;}if(commitError.message.includes('WORKSPACE_CONFLICT')&&attempt<3)continue;throw commitError;}
    }
   }
   const state=restrictView(next,actor);
   await Promise.all(state.products.map(async(p:any)=>{if(p.image?.startsWith('storage:')){const{data}=await admin.storage.from('stockflow-products').createSignedUrl(p.image.slice(8),3600);p.imageUrl=data?.signedUrl||'';}}));
   return json({state,actor});
  }
  return json({error:'The workspace is busy. Refresh and retry.'},409);
 }catch(e){console.error('StockFlow command rejected',e instanceof Error?e.message:'Unknown error');return json({error:e instanceof Error?e.message:'Inventory operation failed.'},400);}
});
