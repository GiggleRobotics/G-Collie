import {test} from 'node:test';import assert from 'node:assert/strict';
import {mkdtemp,readFile,mkdir,rm} from 'node:fs/promises';import {join,resolve} from 'node:path';import {tmpdir} from 'node:os';
import {Readable} from 'node:stream';import {execFileSync} from 'node:child_process';import {existsSync} from 'node:fs';
import {AttachmentStore} from './attachments.js';import {claudeMediaInput} from './claude-media.js';import {claudeEvents} from './claude.js';

test('Claude video streaming validates type, bounds and device/session ownership',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'gcollie-video-'));try{
 const s=new AttachmentStore(dir),session='claude:12345678-1234-1234-1234-123456789012';
 const data=Buffer.concat([Buffer.from([0,0,0,24]),Buffer.from('ftypisom'),Buffer.alloc(12)]);
 const a=await s.addVideo('phone',session,'clip.mp4',data.length,Readable.from([data]));
 assert.equal(a.video,true);assert.equal(a.mime,'video/mp4');assert.throws(()=>s.resolve([a.id],'other',session));
 assert.throws(()=>s.resolve([a.id],'phone','claude:other'));
 await assert.rejects(s.addVideo('phone',session,'bad.mp4',4,Readable.from([Buffer.from('text')])));
 await assert.rejects(s.addVideo('phone',session,'huge.mp4',101*1024*1024,Readable.from([])));
 await assert.rejects(s.addVideo('phone',session,'short.mp4',data.length+1,Readable.from([data])));
 const photo=s.add('phone',session,{name:'photo.png',image:true,data:Buffer.from([137,80,78,71,13,10,26,10]).toString('base64')});assert.equal(photo.image,true);
 }finally{await rm(dir,{recursive:true,force:true})}
});
const ffmpeg=resolve('.tools/ffmpeg/ffmpeg');
test('photos are native image input; video contributes timed frames and original reference', {skip:!existsSync(ffmpeg)},async()=>{
 const dir=await mkdtemp(join(tmpdir(),'gcollie-media-'));try{
 execFileSync(ffmpeg,['-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=blue:s=160x120:d=2','-c:v','libx264','-pix_fmt','yuv420p','-y',join(dir,'video.mp4')]);
 execFileSync(ffmpeg,['-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=yellow:s=160x120','-frames:v','1','-y',join(dir,'photo.png')]);
 const s=new AttachmentStore(dir),session='claude:12345678-1234-1234-1234-123456789012';
 const photo=s.add('phone',session,{name:'photo.png',image:true,data:(await readFile(join(dir,'photo.png'))).toString('base64')});
 const data=await readFile(join(dir,'video.mp4'));const video=await s.addVideo('phone',session,'clip.mp4',data.length,Readable.from([data]));
 const input=await claudeMediaInput('请看附件',s.resolve([photo.id,video.id],'phone',session));
 assert.equal(input.message.content.filter(p=>p.type==='image').length,3);
 assert.match(input.message.content.filter(p=>p.type==='text').map(p=>p.text).join('\n'),/不含音频/);
 const view=claudeEvents([{uuid:'u',message:input.message}]);assert.equal(view.events.length,1);assert.equal(view.events[0].media.length,3);
 assert.ok(view.events[0].media.every((m:string)=>m.startsWith('data:image/jpeg;base64,')));
 }finally{await rm(dir,{recursive:true,force:true})}
});

test('installed-directory image conversion does not depend on repository or system PATH',{skip:!existsSync(ffmpeg)},async()=>{
 const {symlink,writeFile}=await import('node:fs/promises');const {ffmpeg:findFfmpeg}=await import('./claude-media.js');
 const dir=await mkdtemp(join(tmpdir(),'gcollie-installed-media-')),previous=process.cwd(),savedPath=process.env.PATH,savedFfmpeg=process.env.GCOLLIE_FFMPEG;
 try{
  await symlink(savedFfmpeg||ffmpeg,join(dir,'ffmpeg'));delete process.env.GCOLLIE_FFMPEG;
  const png=await readFile(resolve('public/brand/collie-mark-v2.png'));await mkdir(join(dir,'upload'));await writeFile(join(dir,'upload/photo.png'),png);
  process.chdir(dir);process.env.PATH='';assert.equal(findFfmpeg(),join(dir,'ffmpeg'));
  const input=await claudeMediaInput('截图',[{id:'image',device:'phone',session:'codex:test',name:'screen.png',path:join(dir,'upload/photo.png'),mime:'image/png',image:true,size:png.length,createdAt:Date.now()}]);
  assert.equal(input.message.content.filter(p=>p.type==='image').length,1);
 }finally{process.chdir(previous);process.env.PATH=savedPath;if(savedFfmpeg===undefined)delete process.env.GCOLLIE_FFMPEG;else process.env.GCOLLIE_FFMPEG=savedFfmpeg;await rm(dir,{recursive:true,force:true})}
});

const releaseFfmpeg=resolve('.tools/ffmpeg-release/ffmpeg');
test('release JPEG conversion repairs old cache at the same path with scalar CPU encoding',{skip:!existsSync(releaseFfmpeg)},async()=>{
 const {writeFile,stat}=await import('node:fs/promises');const {repairCachedImage,IMAGE_CACHE_VERSION}=await import('./claude-media.js');
 const dir=await mkdtemp(join(tmpdir(),'gcollie-jpeg-regression-')),saved=process.env.GCOLLIE_FFMPEG;
 try{
  process.env.GCOLLIE_FFMPEG=releaseFfmpeg;
  const source=join(dir,'content'),cache=join(dir,'media'),output=join(cache,'image.jpg');
  // Tall phone screenshot dimensions trigger the release encoder regression.
  const ppm=Buffer.concat([Buffer.from('P6\n1200 2670\n255\n'),Buffer.alloc(1200*2670*3,255)]);
  execFileSync(releaseFfmpeg,['-hide_banner','-loglevel','error','-cpuflags','0','-f','image2pipe','-i','pipe:0','-frames:v','1','-y','-f','image2',source],{input:ppm});
  const original=await readFile(source);await mkdir(cache);await writeFile(output,'old corrupt derived cache');
  const values=await Promise.all([repairCachedImage(source),repairCachedImage(source)]);assert.ok(values.every(Boolean));
  assert.deepEqual(await readFile(source),original);
  assert.equal(JSON.parse(await readFile(output+'.version.json','utf8')).version,IMAGE_CACHE_VERSION);
  const pixels=execFileSync(releaseFfmpeg,['-hide_banner','-loglevel','error','-cpuflags','0','-i',output,'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','pipe:1'],{maxBuffer:20*1024*1024});
  assert.equal(pixels.length,920*2048*3);assert.ok(pixels.every(v=>v>250),'white source must remain white, with no colored stripes');
  const first=(await stat(output)).mtimeMs;assert.equal(await repairCachedImage(source),false);assert.equal((await stat(output)).mtimeMs,first);
  await writeFile(output+'.version.json','{}');assert.equal(await repairCachedImage(source),true);
 }finally{if(saved===undefined)delete process.env.GCOLLIE_FFMPEG;else process.env.GCOLLIE_FFMPEG=saved;await rm(dir,{recursive:true,force:true})}
});

test('cache migration repairs existing trusted image only and rejects symlink escape',{skip:!existsSync(releaseFfmpeg)},async()=>{
 const {writeFile,symlink}=await import('node:fs/promises');const {repairImageCaches}=await import('../scripts/repair-image-cache.js');
 const dir=await mkdtemp(join(tmpdir(),'gcollie-migrate-cache-')),saved=process.env.GCOLLIE_FFMPEG;
 try{
  process.env.GCOLLIE_FFMPEG=releaseFfmpeg;const uploads=join(dir,'uploads');await mkdir(uploads);
  const id='qa-image',folder=join(uploads,id),path=join(folder,'content');await mkdir(join(folder,'media'),{recursive:true});
  await writeFile(path,await readFile(resolve('public/brand/collie-mark-v2.png')));
  await writeFile(join(folder,'meta.json'),JSON.stringify({id,image:true,path}));await writeFile(join(folder,'media/image.jpg'),'bad cache');
  const outside=join(dir,'outside');await mkdir(outside);await writeFile(join(outside,'image.jpg'),'unchanged');
  const unsafe=join(uploads,'qa-escape');await mkdir(unsafe);await symlink(outside,join(unsafe,'media'));await writeFile(join(unsafe,'content'),'unchanged');await writeFile(join(unsafe,'meta.json'),'{}');
  const before=await readFile(path);const result=await repairImageCaches(dir);
  assert.equal(result.repaired,1);assert.deepEqual(result.errors,['qa-escape']);assert.deepEqual(await readFile(path),before);assert.equal(await readFile(join(outside,'image.jpg'),'utf8'),'unchanged');
  const again=await repairImageCaches(dir);assert.equal(again.current,1);assert.equal(again.repaired,0);
 }finally{if(saved===undefined)delete process.env.GCOLLIE_FFMPEG;else process.env.GCOLLIE_FFMPEG=saved;await rm(dir,{recursive:true,force:true})}
});
