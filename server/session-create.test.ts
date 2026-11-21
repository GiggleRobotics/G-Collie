import {test} from 'node:test';import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
import {SessionCreation,createNotSubmitted,sessionTitle} from './session-create.js';
test('首次发送创建和提交由同一编号去重，重启也不重放未知结果',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'gcollie-draft-'));
 try{const c=new SessionCreation(dir);let n=0;
 const create=async()=>{n++;return{id:'codex:new'}};
 assert.deepEqual(await c.run('phone','request-1',create),{id:'codex:new'});
 await c.run('phone','request-1',create);assert.equal(n,1);
 await assert.rejects(c.run('phone','request-2',async()=>{throw Error('unknown')}));
 const restarted=new SessionCreation(dir);
 await assert.rejects(restarted.run('phone','request-2',create),/结果未知/);assert.equal(n,1);
 await restarted.run('other-phone','request-1',create);assert.equal(n,2);
 }finally{rmSync(dir,{recursive:true,force:true})}
});
test('标题从首条消息生成，合并空白并按 Unicode 字符截断',()=>{
 assert.equal(sessionTitle('  帮我\n 编写文档  '),'帮我 编写文档');
 assert.equal([...sessionTitle('🐶'.repeat(60))].length,40);
});

test('新建回执按设备隔离，重启后仍可读取，处理中不会重复提交',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'gcollie-create-receipt-'));
 try{
  const creation=new SessionCreation(dir);
  const id='request-123456';
  const result={id:'codex:new',turnId:'turn-1'};
  let finish!:(value:typeof result)=>void;
  const first=creation.run('phone',id,()=>new Promise(resolve=>{finish=resolve}));
  assert.deepEqual(creation.receipt('phone',id),{state:'sending'});
  assert.deepEqual(creation.receipt('another-phone',id),{state:'missing'});
  assert.deepEqual(new SessionCreation(dir).receipt('phone',id),{state:'unknown'});
  await assert.rejects(creation.run('phone',id,async()=>assert.fail('must not run')),{outcome:'sending'});
  finish(result);
  await first;
  const restarted=new SessionCreation(dir);
  assert.deepEqual(restarted.receipt('phone',id),{state:'done',result});
  assert.deepEqual(restarted.receipt('another-phone',id),{state:'missing'});
 }finally{rmSync(dir,{recursive:true,force:true})}
});

test('仅确认未提交的失败可再次手动使用同一请求编号',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'gcollie-create-failed-'));
 try{
  const creation=new SessionCreation(dir);
  const id='request-123456';
  await assert.rejects(creation.run('phone',id,async()=>{throw createNotSubmitted(Error('桌面未连接'))}),{outcome:'failed'});
  const restarted=new SessionCreation(dir);
  assert.deepEqual(restarted.receipt('phone',id),{state:'failed',error:'桌面未连接'});
  assert.deepEqual(await restarted.run('phone',id,async()=>({id:'codex:new'})),{id:'codex:new'});
  await assert.rejects(restarted.run('phone','unknown-123',async()=>{throw Error('断线')}),{outcome:'unknown'});
  assert.deepEqual(restarted.receipt('phone','unknown-123'),{state:'unknown'});
  await assert.rejects(restarted.run('phone','unknown-123',async()=>assert.fail('must not replay')),{outcome:'unknown'});
 }finally{rmSync(dir,{recursive:true,force:true})}
});
