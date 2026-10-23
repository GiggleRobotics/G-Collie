import {test} from 'node:test';import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
import {SessionCreation,sessionTitle} from './session-create.js';
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
