import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,mkdir,symlink,link,rm} from 'node:fs/promises';
import os,{tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import express from 'express';
import {AttachmentStore} from './attachments.js';
import {Readable} from 'node:stream';
import {references,compactDetail,compactReferences,resourceFile,installPreviews} from './resources.js';
const fixture=async()=>{const cwd=await mkdtemp(join(tmpdir(),'collie-resource-'));await writeFile(join(cwd,'report.md'),'# Report\n<script>alert(1)</script>\n[bad](javascript:alert(1))');return {cwd,id:'codex:test',events:[{role:'assistant',text:'[报告](report.md)'}]};};
test('Hermes generated image galleries authorize each explicit image in the home media directory',async t=>{
 const home=await mkdtemp(join(tmpdir(),'collie-hermes-media-'));
 t.mock.method(os,'homedir',()=>home);
 try{
  const folder=join(home,'.media','images','album');
  await mkdir(join(folder,'.private'),{recursive:true});
  const first=join(folder,'第一张.png'),second=join(folder,'second.png');
  const png=Buffer.from('89504e470d0a1a0a','hex');
  await writeFile(first,png);await writeFile(second,png);
  const detail={agent:'Hermes',id:'hermes:gallery',events:[{role:'assistant',media:[first,second]}]};
  const listing=references(detail);
  assert.equal(listing.length,2);
  for(const item of listing){
   const file=await resourceFile(detail,item.id);
   assert.equal(file.image,true);assert.deepEqual(await readFile(file.path),png);
  }
  const lookup=(events:any[],agent='Hermes')=>{
   const d={...detail,agent,events};
   return resourceFile(d,references(d)[0].id);
  };
  await assert.rejects(lookup([{role:'assistant',text:`![link](${first})`}]));
  await assert.rejects(lookup([{role:'user',media:[first]}]));
  await assert.rejects(lookup(detail.events,'Codex'));
  await assert.rejects(resourceFile({...detail,id:'hermes:other'},listing[0].id));
  const privateImage=join(folder,'.private','image.png'),secret=join(folder,'credentials.png');
  const sibling=join(home,'.media','other.png'),doc=join(folder,'notes.txt');
  for(const blocked of [privateImage,secret,sibling,doc]){
   await writeFile(blocked,png);
   await assert.rejects(lookup([{role:'assistant',media:[blocked]}]));
  }
  const outside=join(home,'outside.png'),alias=join(folder,'alias.png');
  await writeFile(outside,png);await symlink(outside,alias);
  await assert.rejects(lookup([{role:'assistant',media:[alias]}]));
 }finally{await rm(home,{recursive:true,force:true});}
});
test('only message references can be read; reject traversal into secret files and symlinks',async()=>{const d=await fixture();const r=references(d)[0];assert.equal((await resourceFile(d,r.id)).name,'report.md');await assert.rejects(resourceFile(d,'a'.repeat(32)));await mkdir(join(d.cwd,'.ssh'));await writeFile(join(d.cwd,'.ssh','key.md'),'secret');await symlink(join(d.cwd,'.ssh','key.md'),join(d.cwd,'leak.md'));d.events.push({role:'assistant',text:'[leak](leak.md)'});await assert.rejects(resourceFile(d,references(d)[1].id));});
test('structured inline image survives projection and validates mime',async()=>{const d={id:'codex:image',events:[{role:'user',media:['data:image/png;base64,aGVsbG8='],text:''}]};const r=references(d)[0];assert.equal(r.image,true);assert.equal((await resourceFile(d,r.id)).data?.toString(),'hello');});
test('browser ticket previews sanitized markdown, supports download and revocation',async()=>{const d=await fixture();let allowed=true;const app=express();const issue=installPreviews(app,async()=>d,()=>allowed);const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));try{const port=(server.address() as any).port;const path=await issue(d.id,references(d)[0].id,'phone');const base='http://127.0.0.1:'+port;const html=await(await fetch(base+path)).text();assert.match(html,/<h1>Report/);const embedded=await(await fetch(base+path+'?embedded=1')).text();assert.doesNotMatch(embedded,/<header>/);assert.match(embedded,/<h1>Report/);assert.doesNotMatch(html,/alert\(1\)/);const download=await fetch(base+path.replace('/view','/content?download=1'));assert.match(download.headers.get('content-disposition')||'',/attachment/);allowed=false;assert.equal((await fetch(base+path)).status,410);}finally{server.close();}});
test('managed video previews inline, supports Range, and remains bound to its session',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'gcollie-video-preview-')),old=process.env.GCOLLIE_DATA_DIR;process.env.GCOLLIE_DATA_DIR=dir;
 const session='claude:12345678-1234-1234-1234-123456789012',store=new AttachmentStore(dir);
 const data=Buffer.concat([Buffer.from([0,0,0,24]),Buffer.from('ftypisom'),Buffer.alloc(12)]);
 const a=await store.addVideo('phone',session,'clip.mp4',data.length,Readable.from([data]));const file=store.resolve([a.id],'phone',session)[0];
 const d={id:session,events:[{role:'user',text:`[clip.mp4](${file.path})`}]};const r=references(d)[0];
 await assert.rejects(resourceFile({...d,id:'claude:other'},references({...d,id:'claude:other'})[0].id));
 const app=express(),issue=installPreviews(app,async()=>d,()=>true),server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 try{const base='http://127.0.0.1:'+(server.address() as any).port,path=await issue(session,r.id,'phone');
 const view=await fetch(base+path+'?embedded=1');assert.match(await view.text(),/<video controls/);assert.match(view.headers.get('content-security-policy')||'',/media-src 'self'/);
 const range=await fetch(base+path.replace('/view','/content'),{headers:{Range:'bytes=0-11'}});assert.equal(range.status,206);assert.equal(range.headers.get('content-type'),'video/mp4');assert.equal((await range.arrayBuffer()).byteLength,12);
 }finally{server.close();if(old===undefined)delete process.env.GCOLLIE_DATA_DIR;else process.env.GCOLLIE_DATA_DIR=old;await rm(dir,{recursive:true,force:true})}
});
test('validated hidden-directory images can be previewed and downloaded, secrets remain blocked',async()=>{const d=await fixture();await mkdir(join(d.cwd,'.codex'));const data=Buffer.from('89504e470d0a1a0a','hex');await writeFile(join(d.cwd,'.codex','screen.png'),data);d.events.push({role:'assistant',text:'![screen](.codex/screen.png)'});const app=express();const issue=installPreviews(app,async()=>d,()=>true);const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));try{const path=await issue(d.id,references(d)[1].id,'phone');const base='http://127.0.0.1:'+(server.address() as any).port;for(const suffix of ['/content','/content?download=1']){const res=await fetch(base+path.replace('/view',suffix));assert.equal(res.status,200);assert.match(res.headers.get('content-type')||'',/image\/png/);assert.deepEqual(Buffer.from(await res.arrayBuffer()),data)}await writeFile(join(d.cwd,'.codex','auth.png'),data);d.events.push({role:'assistant',text:'![secret](.codex/auth.png)'});await assert.rejects(issue(d.id,references(d)[2].id,'phone'));}finally{server.close();await rm(d.cwd,{recursive:true,force:true})}});

test('compact history sends stable image handles without changing authenticated resource lookup',async()=>{
 const ref='data:image/png;base64,'+Buffer.from('image-bytes').toString('base64');
 const d={id:'codex:compact',events:[{id:'one',role:'user',text:'图片',media:[ref]}]};
 const original=references(d)[0],compact=compactDetail(d);
 assert.equal(compact.events[0].media[0],'gcollie-resource:'+original.id);
 assert.equal(compactReferences(d)[0].ref,compact.events[0].media[0]);
 assert.equal(d.events[0].media[0],ref);
 assert.equal((await resourceFile(d,original.id)).data?.toString(),'image-bytes');
 await assert.rejects(resourceFile({...d,id:'codex:other'},original.id));
});

test('repeated video stays at its latest conversation occurrence',()=>{const d={id:'hermes:test',events:[{role:'assistant',media:['/clip.mp4']},{role:'assistant',media:['/one.png','/two.png']},{role:'assistant',media:['/clip.mp4'],text:'[视频](/clip.mp4)'}]};assert.deepEqual(references(d).map(r=>r.ref),['/one.png','/two.png','/clip.mp4']);assert.equal(references(d).length,3)});

test('extensionless uploaded videos preserve the attachment label for media classification',()=>{
 const ref='/home/test/uploads/ba4fe46c-c4fc-4efc-bd6b-be1e12d1d802/content';
 const list=references({id:'codex:video',events:[{role:'user',text:`视频附件：[录屏.mp4](${ref})`}]});
 assert.equal(list[0].name,'录屏.mp4');assert.equal(list[0].ref,ref);assert.equal(list[0].image,false);
});
test('Markdown dependency images are ticket scoped, relative to document, and recheck revocation/traversal',async()=>{
 const d=await fixture();await mkdir(join(d.cwd,'子目录'));await mkdir(join(d.cwd,'.private'));const png=Buffer.from('89504e470d0a1a0a','hex');await writeFile(join(d.cwd,'中文 图片.png'),png);await writeFile(join(d.cwd,'子目录','图片.png'),png);await writeFile(join(d.cwd,'.private','hidden.png'),png);await symlink('/etc/passwd',join(d.cwd,'leak.png'));
 await writeFile(join(d.cwd,'report.md'),'# 报告\n![同目录](中文%20图片.png)\n![子目录](子目录/图片.png)\n![缺失](missing.png)\n![](unnamed.png)\n![隐藏](.private/hidden.png)\n![越界](../outside.png)\n![软链](leak.png)\n![外网](https://example.com/pixel.png)');let allowed=true;const app=express(),issue=installPreviews(app,async()=>d,()=>allowed),server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));try{
 const base='http://127.0.0.1:'+(server.address() as any).port,path=await issue(d.id,references(d)[0].id,'phone'),html=await(await fetch(base+path)).text();const links=[...html.matchAll(/src="(\.\/asset\?id=[a-f0-9]+)"/g)].map(m=>new URL(m[1],base+path).href);assert.equal(links.length,2);assert.match(html,/class="markdown-image-unavailable"[^>]*>缺失<\/span>/);assert.match(html,/class="markdown-image-unavailable"[^>]*>unnamed.png<\/span>/);assert.match(html,/svg.setAttribute\('aria-hidden','true'\)/);assert.match(html,/note.textContent=image.alt\|\|'文档图片'/);assert.doesNotMatch(html,/文件缺失或无权访问|请检查电脑连接后返回重试/);assert.doesNotMatch(html,/src="https:/);
 for(const link of links){const r=await fetch(link);assert.equal(r.status,200);assert.match(r.headers.get('content-type')||'',/image\/png/);assert.deepEqual(Buffer.from(await r.arrayBuffer()),png)}
 assert.equal((await fetch(base+path.replace('/view','/asset?id=arbitrary'))).status,404);
 await writeFile(join(d.cwd,'子目录','图片.png'),'changed');const {unlink}=await import('node:fs/promises');await unlink(join(d.cwd,'子目录','图片.png'));await symlink('/etc/passwd',join(d.cwd,'子目录','图片.png'));assert.equal((await fetch(links[1])).status,404);allowed=false;assert.equal((await fetch(links[0])).status,410);
 }finally{server.close();}
});

test('explicit tool images are session scoped while tool text and non-image media grant no access',async()=>{
 const cwd=await mkdtemp(join(tmpdir(),'collie-tool-image-'));
 try{
 const png=Buffer.from('89504e470d0a1a0a','hex');await writeFile(join(cwd,'screen.png'),png);await writeFile(join(cwd,'other.png'),png);
 const d={id:'codex:tool-image',cwd,events:[{role:'tool',media:['screen.png','report.pdf','https://evil.test/track.png'],text:'![other](other.png)'}]};
 const refs=references(d);assert.deepEqual(refs.map(r=>r.ref),['screen.png']);assert.equal(refs[0].image,true);
 assert.deepEqual(await readFile((await resourceFile(d,refs[0].id)).path),png);
 await assert.rejects(resourceFile({...d,id:'codex:another'},refs[0].id));
 const inline='data:image/png;base64,aGVsbG8=';const data={id:d.id,events:[{role:'tool',media:[inline]}]};
 const id=references(data)[0].id;assert.equal(compactDetail(data).events[0].media[0],'gcollie-resource:'+id);assert.equal((await resourceFile(data,id)).data?.toString(),'hello');
 }finally{await rm(cwd,{recursive:true,force:true})}
});
test('tool image authorization keeps hidden, credential and symlink checks',async()=>{
 const cwd=await mkdtemp(join(tmpdir(),'collie-tool-secret-'));
 try{
 await mkdir(join(cwd,'.private'));await writeFile(join(cwd,'.private','secret.png'),'private');await writeFile(join(cwd,'auth.png'),'private');await symlink(join(cwd,'.private','secret.png'),join(cwd,'alias.png'));
 for(const path of ['.private/secret.png','auth.png','alias.png']){
 const d={id:'codex:tool-secret',cwd,events:[{role:'tool',media:[path]}]};await assert.rejects(resourceFile(d,references(d)[0].id));
 }
 }finally{await rm(cwd,{recursive:true,force:true})}
});


test('tool image file URLs resolve encoded Unicode and spaces without relaxing access checks',async()=>{
 const root=await mkdtemp(join(tmpdir(),'gcollie-file-uri-'));
 try{
  const image=join(root,'红色 图片.png'),hidden=join(root,'.private','禁止.png'),link=join(root,'link.png');
  const png=Buffer.from('89504e470d0a1a0a','hex');
  await mkdir(join(root,'.private'));
  await writeFile(image,png);await writeFile(hidden,png);await symlink(hidden,link);
  const encoded=pathToFileURL(image).href;
  const remote=new URL(encoded);remote.hostname='example.invalid';
  const invalidSlash=encoded.replace('%20','%2F'),invalidBackslash=encoded.replace('%20','%5c');
  const forbidden=[remote.href,invalidSlash,invalidBackslash,pathToFileURL(hidden).href,pathToFileURL(link).href];
  const d={id:'codex:image-uri',cwd:root,events:[{role:'tool',media:[image,encoded,...forbidden]}]};
  const listing=references(d);
  const lookup=(ref:string)=>{const r=listing.find(rec=>rec.ref===ref);assert.ok(r);return resourceFile(d,r.id);};
  const plain=await lookup(image),uri=await lookup(encoded);
  assert.equal(uri.ref,encoded);assert.notEqual(uri.id,plain.id);assert.equal(uri.path,plain.path);
  assert.deepEqual(await readFile(uri.path),png);
  for(const address of forbidden.slice(0,3))await assert.rejects(lookup(address),/不支持此文件地址/);
  for(const blocked of forbidden.slice(3))await assert.rejects(lookup(blocked),/不允许预览/);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('assistant Markdown images in the session workspace build directory preview from validated bytes',async t=>{
 const cwd=await mkdtemp(join(tmpdir(),'gcollie-codex-images-'));
 t.after(()=>rm(cwd,{recursive:true,force:true}));
 const folder=join(cwd,'.packaging','website','qa');
 await mkdir(folder,{recursive:true});
 const fixtures=[
  ['桌面 预览.png','image/png','iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mO4uZULAAQDAZlPBCu3AAAAAElFTkSuQmCC'],
  ['mobile.jpg','image/jpeg','/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABAb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCsAlD3/9k='],
  ['sequence.gif','image/gif','R0lGODdhAQABAIEAANm1CgAAAAAAAAAAACwAAAAAAQABAAAIBAABBAQAOw=='],
  ['crop.webp','image/webp','UklGRjgAAABXRUJQVlA4ICwAAACQAQCdASoBAAEAAsBMJaACdLoAA5gA/uu3r/00j/hh/+GH+MH8UApHAeAAAA=='],
 ];
 const detail={id:'codex:review',agent:'Codex',cwd,events:[{role:'assistant',text:''}]};
 for(const [name,mime,encoded] of fixtures){
  const bytes=Buffer.from(encoded,'base64'),abs=join(folder,name);
  const ref=mime==='image/png'?abs:'.packaging/website/qa/'+name;
  await writeFile(abs,bytes);
  detail.events[0].text+='\n![预览](<'+ref+'>)';
  const resource=references(detail).find(r=>r.ref===ref)!;
  const file=await resourceFile(detail,resource.id);
  assert.equal(file.mime,mime);assert.deepEqual(file.data,bytes);assert.equal(file.path,'');
 }
 const app=express();let allowed=true;
 const issue=installPreviews(app,async()=>detail,()=>allowed);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));t.after(()=>server.close());
 const base='http://127.0.0.1:'+(server.address() as any).port;
 const preview=await issue(detail.id,references(detail)[0].id,'paired-phone');
 const content=base+preview.replace('/view','/content');
 for(const url of [content,content+'?download=1']){
  const response=await fetch(url);assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'image/png');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()),Buffer.from(fixtures[0][2],'base64'));
 }
 allowed=false;assert.equal((await fetch(content)).status,410);
});

test('build output images require an explicit assistant image, canonical location and matching raster bytes',async t=>{
 const cwd=await mkdtemp(join(tmpdir(),'gcollie-codex-private-')),folder=join(cwd,'.packaging','review');
 t.after(()=>rm(cwd,{recursive:true,force:true}));
 await mkdir(folder,{recursive:true});
 const img=join(folder,'result.png'),png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mO4uZULAAQDAZlPBCu3AAAAAElFTkSuQmCC','base64');await writeFile(img,png);
 const markdown=(ref:string)=>'![图](<'+ref+'>)';
 const detail={id:'codex:private',agent:'Codex',cwd,events:[{role:'assistant',text:markdown(img)}]};
 async function denied(events:any[],ref=img,other={}){
  const d={...detail,...other,events};const r=references(d).find(x=>x.ref===ref);assert(r,ref);
  await assert.rejects(resourceFile(d,r.id),/不允许预览/);
 }
 for(const event of [{role:'user',text:markdown(img)},{role:'assistant',text:'[普通文件](<'+img+'>)'},{role:'assistant',text:'`'+markdown(img)+'`'},{role:'assistant',text:'\n```md\n'+markdown(img)+'\n```'},{role:'tool',media:[img]},{role:'user',media:[img]}])await denied([event]);
 await denied(detail.events,img,{cwd:'',projectPath:cwd});
 await denied(detail.events,img,{cwd:join(cwd,'other')});
 await assert.rejects(resourceFile({...detail,id:'codex:other'},references(detail)[0].id),/未被此会话引用/);
 await mkdir(join(folder,'.private'));await mkdir(join(folder,'credentials'));
 const outside=join(cwd,'outside.png');await writeFile(outside,png);
 const outsideLink=join(folder,'outside.png'),insideLink=join(folder,'alias.png'),outsideAlias=join(cwd,'alias.png'),hard=join(folder,'hard.png');
 await symlink(outside,outsideLink);await symlink(img,insideLink);await symlink(img,outsideAlias);await link(outside,hard);
 const nested=join(folder,'.private','result.png'),secret=join(folder,'credentials','result.png'),spoof=join(folder,'fake.png'),mismatch=join(folder,'wrong.jpg');
 await writeFile(nested,png);await writeFile(secret,png);await writeFile(spoof,'private text');await writeFile(mismatch,png);
 for(const ref of [nested,secret,spoof,mismatch,outsideLink,insideLink,outsideAlias,hard,folder+'/../review/result.png']){
  await denied([{role:'assistant',text:markdown(ref)}],ref);
 }
});

test('project images follow session evidence across providers and control modes',async t=>{
 const cwd=await mkdtemp(join(tmpdir(),'gcollie-session-evidence-'));
 t.after(()=>rm(cwd,{recursive:true,force:true}));
 const folder=join(cwd,'.packaging','qa'),ref='.packaging/qa/result.png';
 await mkdir(folder,{recursive:true});
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mO4uZULAAQDAZlPBCu3AAAAAElFTkSuQmCC','base64');
 await writeFile(join(cwd,ref),png);
 for(const session of [
  {id:'codex:desktop',agent:'Codex'},
  {id:'codex:headless',agent:'Codex',readOnly:true,archived:true},
  {id:'hermes:history',agent:'Hermes'},
  {id:'claude:5885bde1-e624-4381-9af0-b744c5fb2698',agent:'Claude Code'},
  {id:'managed:native',agent:'Codex'},
  {id:'opaque-valid-key'},
 ]){
  for(const event of [{role:'assistant',text:'![result]('+ref+')'},{role:'assistant',media:[ref]}]){
   const d={...session,cwd,events:[event]},r=references(d)[0];
   assert.deepEqual((await resourceFile(d,r.id)).data,png,session.id);
   await assert.rejects(resourceFile({...d,id:'other-session'},r.id),/未被此会话引用/);
   await assert.rejects(resourceFile({...d,events:[{role:'user',media:[ref]}]},r.id),/不允许预览/);
  }
 }
 // A linked Markdown file is a document, even when the assistant authored its link.
 const d={cwd,id:'hermes:doc',events:[{role:'assistant',text:'[report](report.md)'}]};
 await writeFile(join(cwd,'report.md'),'![图]('+ref+')');
 const app=express(),issue=installPreviews(app,async()=>d,()=>true),server=app.listen(0,'127.0.0.1');
 await new Promise<void>(resolve=>server.once('listening',resolve));t.after(()=>server.close());
 const path=await issue(d.id,references(d)[0].id,'phone');
 const html=await (await fetch('http://127.0.0.1:'+(server.address() as any).port+path)).text();
 assert.match(html,/markdown-image-unavailable/);assert.doesNotMatch(html,/src="\.\/asset/);
});
