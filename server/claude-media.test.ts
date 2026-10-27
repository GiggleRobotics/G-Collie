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
 const dir=await mkdtemp(join(tmpdir(),'gcollie-installed-media-')),previous=process.cwd(),savedPath=process.env.PATH;
 try{
  await symlink(ffmpeg,join(dir,'ffmpeg'));
  const png=await readFile(resolve('public/brand/collie-mark-v2.png'));await mkdir(join(dir,'upload'));await writeFile(join(dir,'upload/photo.png'),png);
  process.chdir(dir);process.env.PATH='';assert.equal(findFfmpeg(),join(dir,'ffmpeg'));
  const input=await claudeMediaInput('截图',[{id:'image',device:'phone',session:'codex:test',name:'screen.png',path:join(dir,'upload/photo.png'),mime:'image/png',image:true,size:png.length,createdAt:Date.now()}]);
  assert.equal(input.message.content.filter(p=>p.type==='image').length,1);
 }finally{process.chdir(previous);process.env.PATH=savedPath;await rm(dir,{recursive:true,force:true})}
});
