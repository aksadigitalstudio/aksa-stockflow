import {mkdir,copyFile} from 'node:fs/promises';
await mkdir('supabase/functions/_shared',{recursive:true});
for(const file of ['config.js','domain.js'])await copyFile('src/'+file,'supabase/functions/_shared/'+file);
console.log('Server command reducer synchronized from the application source.');
