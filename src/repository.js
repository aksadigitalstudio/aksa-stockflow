import {createClient} from '@supabase/supabase-js';
import {CONFIG,DEMO_USERS} from './config.js';
import {createDemo} from './seed.js';
import {executeCommand,restrictView,validateState,uid} from './domain.js';
const url=import.meta.env.VITE_SUPABASE_URL,key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const cloud=!!(url&&key);
export const supabase=cloud?createClient(url,key):null;
const channel=typeof BroadcastChannel!=='undefined'?new BroadcastChannel(CONFIG.storageKey):null;
let db,listener=()=>{};
function openDB(){return new Promise((resolve,reject)=>{const req=indexedDB.open(CONFIG.storageKey,1);req.onupgradeneeded=()=>req.result.createObjectStore('workspace');req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});}
async function transaction(command,actor){db??=await openDB();return new Promise((resolve,reject)=>{const tx=db.transaction('workspace','readwrite'),store=tx.objectStore('workspace'),request=store.get('state');let result;request.onsuccess=()=>{try{const current=request.result||createDemo();validateState(current);result=command?executeCommand(current,command,actor):current;store.put(result,'state');}catch(e){reject(e);tx.abort();}};tx.oncomplete=()=>resolve(result);tx.onerror=()=>reject(new Error('Unable to save inventory. Browser storage may be full. No changes were committed.'));tx.onabort=()=>reject(new Error('The inventory transaction was cancelled.'));});}
async function invoke(body){const{data,error}=await supabase.functions.invoke('stockflow',{body});if(error){let message=error.message;try{message=(await error.context.json()).error||message;}catch{}throw new Error(message);}if(data.error)throw new Error(data.error);return data;}
export const repository={
 mode:cloud?'Supabase':'Demo Mode',
 async read(actor){if(cloud)return invoke({action:'read'});const state=await transaction();return{state:restrictView(state,actor),actor};},
 async dispatch(type,data,actor,id=uid()){if(cloud){const result=await invoke({action:'command',command:{type,data,id}});listener();return result;}const state=await transaction({type,data,id},actor);channel?.postMessage('changed');listener();return{state:restrictView(state,actor),actor};},
 async user(){if(!cloud)return DEMO_USERS.find(x=>x.id===localStorage.getItem('stockflow-actor'))||DEMO_USERS[0];const{data}=await supabase.auth.getSession();return data.session?.user||null;},
 async signIn(email,password){const{error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error;},
 async signOut(){if(cloud)await supabase.auth.signOut();},
 subscribe(fn){listener=fn;channel&&(channel.onmessage=fn);return()=>listener=()=>{};},
 async backup(){if(cloud)throw new Error('Use database backups for the cloud workspace.');return transaction();},
};
