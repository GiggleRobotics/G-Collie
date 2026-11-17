import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import express from 'express';
import {references,installPreviews} from './resources.js';
const fixture=async()=>{const cwd=await mkdtemp(join(tmpdir(),'collie-markdown-'));await writeFile(join(cwd,'report.md'),'# Report');return {cwd,id:'codex:qa-markdown',events:[{role:'assistant',text:'[报告](report.md)'}]};};

test('Markdown loads authorized images eagerly and gives text feedback for late/offline image failures only',async()=>{
 const d=await fixture();await mkdir(join(d.cwd,'子目录'));
 for(const name of ['中文 图.png','子目录/图.png'])await writeFile(join(d.cwd,name),Buffer.from('89504e470d0a1a0a','hex'));
 await writeFile(join(d.cwd,'report.md'),'# Inline\n![同目录](中文%20图.png)\n![子目录](子目录/图.png)\n![missing](missing.png)\n![absolute](/etc/test.png)\n![remote](https://example.invalid/test.png)');
 const app=express(),issue=installPreviews(app,async()=>d,()=>true),server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 try{
  const base='http://127.0.0.1:'+(server.address() as any).port,path=await issue(d.id,references(d)[0].id,'qa');const html=await(await fetch(base+path)).text();
  assert.equal((html.match(/loading="eager"/g)||[]).length,2);assert.match(html,/图片不可用/);assert.doesNotMatch(html,/src="(?:https:|\/etc)/);
  const source=html.match(/<script>(\(\(\)=>\{for\(const image[\s\S]*?)<\/script>/)?.[1];assert.ok(source);
  const {runInNewContext}=await import('node:vm');const notes:string[]=[],callbacks:(()=>void)[]=[];
  const images=[{complete:false,naturalWidth:0},{complete:true,naturalWidth:0},{complete:true,naturalWidth:320}].map((state,i)=>({...state,addEventListener:(name:string,fn:()=>void)=>{assert.equal(name,'error');callbacks[i]=fn},replaceWith:(node:{textContent:string})=>notes.push(node.textContent)}));
  runInNewContext(source,{document:{querySelectorAll:(selector:string)=>{assert.equal(selector,'main img');return images},createElement:(tag:string)=>{assert.equal(tag,'span');return{textContent:''}}}});
  assert.equal(notes.length,1,'already failed cached image is explained');callbacks[0]();assert.equal(notes.length,2,'later resource/network failure is explained');assert.ok(notes.every(t=>t==='图片加载失败，请检查电脑连接后返回重试。'));
 }finally{await new Promise<void>(r=>server.close(()=>r()));await rm(d.cwd,{recursive:true,force:true})}
});
