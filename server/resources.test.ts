import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir,symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import express from 'express';
import {references,compactDetail,compactReferences,resourceFile,installPreviews} from './resources.js';
const fixture=async()=>{const cwd=await mkdtemp(join(tmpdir(),'collie-resource-'));await writeFile(join(cwd,'report.md'),'# Report\n<script>alert(1)</script>\n[bad](javascript:alert(1))');return {cwd,id:'codex:test',events:[{role:'assistant',text:'[报告](report.md)'}]};};
test('only message references can be read; reject traversal into secret files and symlinks',async()=>{const d=await fixture();const r=references(d)[0];assert.equal((await resourceFile(d,r.id)).name,'report.md');await assert.rejects(resourceFile(d,'a'.repeat(32)));await mkdir(join(d.cwd,'.ssh'));await writeFile(join(d.cwd,'.ssh','key.md'),'secret');await symlink(join(d.cwd,'.ssh','key.md'),join(d.cwd,'leak.md'));d.events.push({role:'assistant',text:'[leak](leak.md)'});await assert.rejects(resourceFile(d,references(d)[1].id));});
test('structured inline image survives projection and validates mime',async()=>{const d={id:'codex:image',events:[{role:'user',media:['data:image/png;base64,aGVsbG8='],text:''}]};const r=references(d)[0];assert.equal(r.image,true);assert.equal((await resourceFile(d,r.id)).data?.toString(),'hello');});
test('browser ticket previews sanitized markdown, supports download and revocation',async()=>{const d=await fixture();let allowed=true;const app=express();const issue=installPreviews(app,async()=>d,()=>allowed);const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));try{const port=(server.address() as any).port;const path=await issue(d.id,references(d)[0].id,'phone');const base='http://127.0.0.1:'+port;const html=await(await fetch(base+path)).text();assert.match(html,/<h1>Report/);const embedded=await(await fetch(base+path+'?embedded=1')).text();assert.doesNotMatch(embedded,/<header>/);assert.match(embedded,/<h1>Report/);assert.doesNotMatch(html,/alert\(1\)/);const download=await fetch(base+path.replace('/view','/content?download=1'));assert.match(download.headers.get('content-disposition')||'',/attachment/);allowed=false;assert.equal((await fetch(base+path)).status,410);}finally{server.close();}});
import {AttachmentStore} from './attachments.js';import {Readable} from 'node:stream';import {rm} from 'node:fs/promises';
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
 await writeFile(join(d.cwd,'report.md'),'# 报告\n![同目录](中文%20图片.png)\n![子目录](子目录/图片.png)\n![缺失](missing.png)\n![隐藏](.private/hidden.png)\n![越界](../outside.png)\n![软链](leak.png)\n![外网](https://example.com/pixel.png)');let allowed=true;const app=express(),issue=installPreviews(app,async()=>d,()=>allowed),server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));try{
 const base='http://127.0.0.1:'+(server.address() as any).port,path=await issue(d.id,references(d)[0].id,'phone'),html=await(await fetch(base+path)).text();const links=[...html.matchAll(/src="(\.\/asset\?id=[a-f0-9]+)"/g)].map(m=>new URL(m[1],base+path).href);assert.equal(links.length,2);assert.match(html,/图片不可用/);assert.doesNotMatch(html,/src="https:/);
 for(const link of links){const r=await fetch(link);assert.equal(r.status,200);assert.match(r.headers.get('content-type')||'',/image\/png/);assert.deepEqual(Buffer.from(await r.arrayBuffer()),png)}
 assert.equal((await fetch(base+path.replace('/view','/asset?id=arbitrary'))).status,404);
 await writeFile(join(d.cwd,'子目录','图片.png'),'changed');const {unlink}=await import('node:fs/promises');await unlink(join(d.cwd,'子目录','图片.png'));await symlink('/etc/passwd',join(d.cwd,'子目录','图片.png'));assert.equal((await fetch(links[1])).status,404);allowed=false;assert.equal((await fetch(links[0])).status,410);
 }finally{server.close();}
});
