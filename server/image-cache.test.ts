import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm,symlink,stat,readdir} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {existsSync} from 'node:fs';
import {repairImageCaches} from './image-cache.js';
import {IMAGE_CACHE_VERSION} from './claude-media.js';
const binary=resolve('.tools/ffmpeg-release/ffmpeg');
async function fixture(){const dir=await mkdtemp(join(tmpdir(),'gcollie-cache-safety-'));await mkdir(join(dir,'uploads'));return dir}
async function attachment(root:string,id:string){const dir=join(root,'uploads',id),path=join(dir,'content');await mkdir(join(dir,'media'),{recursive:true});const source=await readFile(resolve('public/brand/collie-mark-v2.png'));await writeFile(path,source);await writeFile(join(dir,'meta.json'),JSON.stringify({id,image:true,path}));await writeFile(join(dir,'media/image.jpg'),'old broken derivative');return{dir,path,source,cache:join(dir,'media/image.jpg')}}
async function useBinary(fn:()=>Promise<void>){const old=process.env.GCOLLIE_FFMPEG;process.env.GCOLLIE_FFMPEG=binary;try{await fn()}finally{if(old===undefined)delete process.env.GCOLLIE_FFMPEG;else process.env.GCOLLIE_FFMPEG=old}}

test('existing derivative is atomically repaired at historical path; source and chats stay byte identical; repeated pass is current',{skip:!existsSync(binary)},async()=>{
 const root=await fixture();try{await useBinary(async()=>{
  const a=await attachment(root,'phone-image');const chat=join(root,'chat.json');await writeFile(chat,'private chat sentinel');
  const first=await repairImageCaches(root);assert.equal(first.repaired,1);assert.deepEqual(first.errors,[]);
  assert.deepEqual(await readFile(a.path),a.source);assert.equal(await readFile(chat,'utf8'),'private chat sentinel');
  const jpeg=await readFile(a.cache);assert.equal(jpeg[0],255);assert.equal(jpeg[1],216);
  assert.equal(JSON.parse(await readFile(a.cache+'.version.json','utf8')).version,IMAGE_CACHE_VERSION);
  const mtime=(await stat(a.cache)).mtimeMs;const second=await repairImageCaches(root);assert.equal(second.current,1);assert.equal(second.repaired,0);assert.equal((await stat(a.cache)).mtimeMs,mtime);
  assert.deepEqual((await readdir(a.dir)).sort(),['content','media','meta.json']);
 })}finally{await rm(root,{recursive:true,force:true})}
});

test('unconverted source attachment is skipped without creating cache',{skip:!existsSync(binary)},async()=>{
 const root=await fixture();try{const a=await attachment(root,'no-cache');await rm(join(a.dir,'media'),{recursive:true});const result=await repairImageCaches(root);assert.equal(result.scanned,0);assert.equal(result.repaired,0);assert.equal(result.skipped,1);assert.equal(existsSync(join(a.dir,'media')),false);assert.deepEqual(await readFile(a.path),a.source)}finally{await rm(root,{recursive:true,force:true})}
});

test('missing source with old cache is a failure, never current or repaired',{skip:!existsSync(binary)},async()=>{
 const root=await fixture();try{const a=await attachment(root,'missing-source');await rm(a.path);const result=await repairImageCaches(root);assert.deepEqual(result.errors,['missing-source']);assert.equal(result.repaired,0);assert.equal(result.current,0);assert.equal(await readFile(a.cache,'utf8'),'old broken derivative');assert.equal(existsSync(a.cache+'.version.json'),false)}finally{await rm(root,{recursive:true,force:true})}
});

test('metadata identity, image classification and original path mismatches cannot rewrite cached files',{skip:!existsSync(binary)},async()=>{
 const root=await fixture();try{
  for(const [id,override] of [['wrong-id',{id:'elsewhere'}],['not-image',{image:false}],['wrong-path',{path:'/tmp/unrelated'}]] as const){const a=await attachment(root,id);await writeFile(join(a.dir,'meta.json'),JSON.stringify(Object.assign({id,image:true,path:a.path},override)))}
  const result=await repairImageCaches(root);assert.deepEqual(result.errors.sort(),['not-image','wrong-id','wrong-path']);assert.equal(result.repaired,0);
  for(const id of result.errors)assert.equal(await readFile(join(root,'uploads',id,'media/image.jpg'),'utf8'),'old broken derivative');
 }finally{await rm(root,{recursive:true,force:true})}
});

test('source, metadata, cache directory, output and version-marker symlinks cannot escape migration',{skip:!existsSync(binary)},async()=>{
 const root=await fixture();try{
  const outside=join(root,'outside');await mkdir(outside);await writeFile(join(outside,'sentinel'),'outside retained');
  for(const kind of ['source','metadata','cache','output','marker']){
   const a=await attachment(root,kind);let target:string;
   if(kind==='cache'){target=join(a.dir,'media');await rm(target,{recursive:true});await writeFile(join(outside,'image.jpg'),'outside retained');await symlink(outside,target)}
   else{target=kind==='source'?a.path:kind==='metadata'?join(a.dir,'meta.json'):kind==='output'?a.cache:a.cache+'.version.json';await rm(target,{force:true});await symlink(join(outside,'sentinel'),target)}
  }
  const result=await repairImageCaches(root);assert.deepEqual(result.errors.sort(),['cache','marker','metadata','output','source']);assert.equal(result.repaired,0);assert.equal(await readFile(join(outside,'sentinel'),'utf8'),'outside retained');assert.equal(await readFile(join(outside,'image.jpg'),'utf8'),'outside retained');
 }finally{await rm(root,{recursive:true,force:true})}
});

test('decoder failure preserves existing derivative and original without stamping success',{skip:!existsSync(binary)},async()=>{
 const root=await fixture();try{await useBinary(async()=>{
  const a=await attachment(root,'decode-failure');await writeFile(a.path,'invalid original image sentinel');
  const result=await repairImageCaches(root);assert.deepEqual(result.errors,['decode-failure']);assert.equal(result.repaired,0);assert.equal(result.current,0);
  assert.equal(await readFile(a.path,'utf8'),'invalid original image sentinel');assert.equal(await readFile(a.cache,'utf8'),'old broken derivative');assert.equal(existsSync(a.cache+'.version.json'),false);assert.deepEqual((await readdir(join(a.dir,'media'))).sort(),['image.jpg']);
 })}finally{await rm(root,{recursive:true,force:true})}
});
