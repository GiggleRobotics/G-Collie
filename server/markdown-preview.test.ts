import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import express from 'express';
import {references,installPreviews} from './resources.js';
const fixture=async()=>{const cwd=await mkdtemp(join(tmpdir(),'collie-markdown-'));await writeFile(join(cwd,'report.md'),'# Report');return {cwd,id:'codex:qa-markdown',events:[{role:'assistant',text:'[报告](report.md)'}]};};

test('Markdown loads authorized images eagerly and shows only an icon and image name for missing and late/offline image failures',async()=>{
 const d=await fixture();await mkdir(join(d.cwd,'子目录'));
 for(const name of ['中文 图.png','子目录/图.png'])await writeFile(join(d.cwd,name),Buffer.from('89504e470d0a1a0a','hex'));
 await writeFile(join(d.cwd,'report.md'),'# Inline\n![同目录](中文%20图.png)\n![子目录](子目录/图.png)\n![missing](missing.png)\n![absolute](/etc/test.png)\n![remote](https://example.invalid/test.png)');
 const app=express(),issue=installPreviews(app,async()=>d,()=>true),server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 try{
  const base='http://127.0.0.1:'+(server.address() as any).port,path=await issue(d.id,references(d)[0].id,'qa');const html=await(await fetch(base+path)).text();
  assert.equal((html.match(/loading="eager"/g)||[]).length,2);assert.match(html,/class="markdown-image-unavailable"[^>]*>missing<\/span>/);assert.doesNotMatch(html,/文件缺失或无权访问|请检查电脑连接后返回重试/);assert.doesNotMatch(html,/src="(?:https:|\/etc)/);
  const source=html.match(/<script>(\(\(\)=>\{const decorate[\s\S]*?)<\/script>/)?.[1];assert.ok(source);
  const {runInNewContext}=await import('node:vm');const notes:any[]=[],callbacks:(()=>void)[]=[];
  const node=(tag:string)=>({tag,textContent:'',className:'',title:'',style:{cssText:'',flexShrink:''},attributes:{} as Record<string,string>,children:[] as any[],setAttribute(name:string,value:string){this.attributes[name]=value},append(child:any){this.children.push(child)},prepend(child:any){this.children.unshift(child)}});
  const missing=node('span');missing.textContent='missing';
  const images=[{complete:false,naturalWidth:0,alt:'稍后失败图片'},{complete:true,naturalWidth:0,alt:'缓存失败图片'},{complete:true,naturalWidth:320,alt:'正常图片'}].map((state,i)=>({...state,addEventListener:(name:string,fn:()=>void)=>{assert.equal(name,'error');callbacks[i]=fn},replaceWith:(replacement:any)=>notes.push(replacement)}));
  runInNewContext(source,{document:{querySelectorAll:(selector:string)=>{if(selector==='main .markdown-image-unavailable')return[missing];assert.equal(selector,'main img');return images},createElement:(tag:string)=>{assert.equal(tag,'span');return node(tag)},createElementNS:(_namespace:string,tag:string)=>node(tag)}});
  assert.equal(missing.children[0].tag,'svg','missing file receives a broken-image icon');
  assert.equal(notes.length,1,'already failed cached image receives an icon and name');callbacks[0]();assert.equal(notes.length,2,'later resource/network failure receives an icon and name');
  assert.deepEqual(notes.map(n=>n.textContent),['缓存失败图片','稍后失败图片']);
  for(const note of notes){assert.equal(note.children[0].tag,'svg');assert.equal(note.children[0].attributes['aria-hidden'],'true');assert.equal(note.title,'图片加载失败');assert.equal(note.attributes['aria-label'],note.textContent+'：图片加载失败')}

 }finally{await new Promise<void>(r=>server.close(()=>r()));await rm(d.cwd,{recursive:true,force:true})}
});
