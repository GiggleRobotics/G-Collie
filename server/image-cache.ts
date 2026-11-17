/** Upgrade derived image caches only; source attachments and chat records stay intact. */
import {readdir,readFile,realpath,lstat} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {repairCachedImage} from './claude-media.js';
export async function repairImageCaches(dataDir:string){
 const root=await realpath(join(dataDir,'uploads'));
 const result={scanned:0,repaired:0,current:0,skipped:0,errors:[] as string[]};
 for(const id of await readdir(root)){
  if(!/^[a-zA-Z0-9_-]+$/.test(id)){result.skipped++;continue}
  const dir=join(root,id),source=join(dir,'content'),meta=join(dir,'meta.json'),cache=join(dir,'media'),output=join(cache,'image.jpg');
  try{
   // Only existing regular derived files with matching regular original metadata.
   const d=await lstat(dir);if(!d.isDirectory()||d.isSymbolicLink()){result.skipped++;continue}
   let o;try{o=await lstat(output)}catch{result.skipped++;continue}
   result.scanned++;
   for(const p of [dir,source,meta,cache,output])if(await realpath(p)!==p||(await lstat(p)).isSymbolicLink())throw Error('unsafe path');
   if(!o.isFile()||!(await lstat(source)).isFile()||!(await lstat(meta)).isFile()||!(await lstat(cache)).isDirectory())throw Error('invalid file');
   const m=JSON.parse(await readFile(meta,'utf8'));
   if(m.id!==id||m.image!==true||resolve(m.path||'')!==source)throw Error('metadata mismatch');
   const marker=output+'.version.json';try{if((await lstat(marker)).isSymbolicLink())throw Error('unsafe marker')}catch(e:any){if(e.code!=='ENOENT')throw e}
   if(await repairCachedImage(source))result.repaired++;else result.current++;
  }catch{result.errors.push(id)}
 }
 return result;
}
