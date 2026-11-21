import{test}from'node:test';import assert from'node:assert/strict';import{mkdirSync,mkdtempSync,rmSync,writeFileSync}from'node:fs';import{tmpdir}from'node:os';import{join}from'node:path';import{DesktopCreator}from'./desktop-create.js';
import{createNotSubmitted}from'./session-create.js';
test('Codex 新建只接受本地项目，并且成功结果不重复创建',async()=>{const root=mkdtempSync(join(tmpdir(),'orbit-create-'));try{const c:any=new DesktopCreator(root);let creates=0;c.tool=async(name:string,args:any)=>{if(name==='list_projects')return{projects:[{projectId:'p',projectKind:'local',hostId:'local',path:'/project'}]};creates++;assert.deepEqual(args.target,{type:'project',projectId:'p',environment:{type:'local'}});return{threadId:'test-id'}};const b={requestId:'request-001',prompt:'test',title:'test',cwd:'/project'};assert.equal((await c.create(b)).id,'codex:test-id');assert.equal((await c.create(b)).id,'codex:test-id');assert.equal(creates,1);await assert.rejects(c.create({...b,requestId:'request-002',cwd:'/unknown'}));assert.equal(creates,1)}finally{rmSync(root,{recursive:true,force:true})}});
test('Codex 新建超时后不重放；无项目使用桌面 projectless',async()=>{const root=mkdtempSync(join(tmpdir(),'orbit-create-'));try{const c:any=new DesktopCreator(root);let creates=0;c.tool=async(name:string,args:any)=>{if(name==='list_projects')return{projects:[]};creates++;assert.deepEqual(args.target,{type:'projectless'});throw Error('timeout')};const b={requestId:'request-003',prompt:'test',title:'test',cwd:''};await assert.rejects(c.create(b),/timeout/);await assert.rejects(c.create(b),/结果未知/);assert.equal(creates,1)}finally{rmSync(root,{recursive:true,force:true})}});
test('显式选择的新目录可创建原生目录会话，同一编号只发送一次首条消息',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-folder-start-'));
 try{let calls=0;const c:any=new DesktopCreator(root,async(cwd,b)=>{calls++;assert.equal(cwd,'/new-folder');assert.equal(b.prompt,'first');return{threadId:'native-folder'}});
 c.tool=async()=>({projects:[]});const b={requestId:'folder-request',prompt:'first',cwd:'/new-folder',folderSelected:true};
 assert.equal((await c.create(b)).id,'codex:native-folder');await c.create(b);assert.equal(calls,1);
 await assert.rejects(c.create({...b,folderSelected:false,requestId:'not-selected'}),/未找到/);
 }finally{rmSync(root,{recursive:true,force:true})}
});

test('independent creation never invokes cross-task create tool and deduplicates result',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-independent-'));
 try{let calls=0;const c:any=new DesktopCreator(root,undefined,async(b:any)=>{calls++;return{threadId:'direct',turnId:'turn-direct'}});
 c.tool=async()=>{throw Error('cross-task tool must not run')};
 const b={requestId:'independent-request',prompt:'first',cwd:''};
 assert.deepEqual(await c.create(b),{id:'codex:direct',nativeId:'direct',turnId:'turn-direct'});
 assert.deepEqual(await c.create(b),{id:'codex:direct',nativeId:'direct',turnId:'turn-direct'});assert.equal(calls,1);
 }finally{rmSync(root,{recursive:true,force:true})}
});

test('导航可使用目标会话作为调用上下文，不依赖保存的其他任务',async()=>{const root=mkdtempSync(join(tmpdir(),'gcollie-nav-'));try{const c:any=new DesktopCreator(root);c.runtime={};let params:any;c.rpc=async(_:string,p:any)=>{params=p;return{success:true,contentItems:[{type:'inputText',text:'{}'}]}};await c.load('target-thread');assert.equal(params.threadId,'target-thread');assert.equal(params.arguments.threadId,'target-thread');}finally{rmSync(root,{recursive:true,force:true})}});

test('quota read reloads desktop runtime after account/runtime replacement',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-account-switch-'));
 try{const c:any=new DesktopCreator(root);c.runtime={pipe:'old-pipe',context:'old-thread'};
 writeFileSync(join(root,'desktop-runtime.json'),JSON.stringify({pipe:'new-pipe',context:'new-thread'}));
 c.rpc=async(_:string,p:any)=>{assert.equal(c.runtime.pipe,'new-pipe');assert.equal(p.threadId,'new-thread');assert.equal(p.tool,'get_usage_limits');return{success:true,contentItems:[{type:'inputText',text:'{"rateLimits":{}}'}]}};
 await c.usageLimits();
 }finally{rmSync(root,{recursive:true,force:true})}
});

test('桌面工具迁移到专用目录后可自动发现，旧目录仍兼容',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-desktop-tools-'));
 try{
  const current=join(root,'current'),legacy=join(root,'legacy');
  for(const path of [current,legacy]){mkdirSync(path,{mode:0o700});writeFileSync(join(path,'aaaa.sock'),'')}
  const f=new DesktopCreator(root) as any;
  f.toolsDirectories=()=>[current,legacy];
  f.runtime={pipe:join(root,'stale.sock'),context:'old-thread'};
  const seen:string[]=[];
  f.rpcAt=async(path:string,method:string,_params:any)=>{
   seen.push(path);
   if(method==='tools/call')return{success:true,contentItems:[{type:'inputText',text:'{}'}]};
   if(path===join(current,'aaaa.sock'))return{tools:[{name:'create_thread'}]};
   throw Error('No handler registered for method: tools/list');
  };
  await f.load('target-thread');
  assert.deepEqual(seen,[join(root,'stale.sock'),join(current,'aaaa.sock'),join(current,'aaaa.sock')]);
  assert.equal(f.runtime.pipe,join(current,'aaaa.sock'));

  f.runtime.pipe=undefined;
  f.rpcAt=async(path:string,method:string)=>{
   if(method==='tools/call')return{success:true,contentItems:[{type:'inputText',text:'{}'}]};
   if(path===join(legacy,'aaaa.sock'))return{tools:[{name:'create_thread'}]};
   throw Error('unsupported');
  };
  assert.equal((await f.status()).available,true);
  assert.equal(f.runtime.pipe,join(legacy,'aaaa.sock'));
 }finally{rmSync(root,{recursive:true,force:true})}
});

test('桌面已创建且确认首条未提交时，重启后继续同一会话',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-create-checkpoint-'));
 try{
  const b={requestId:'request-123456',prompt:'first',cwd:'/project'};
  const first=new DesktopCreator(root,undefined,async(_,{prepared,savePrepared})=>{
   assert.equal(prepared,undefined);
   savePrepared('existing-thread');
   throw createNotSubmitted(Error('未收到桌面快照'));
  });
  await assert.rejects(first.create(b),{outcome:'failed'});
  let sends=0;
  const restarted=new DesktopCreator(root,undefined,async(_,{prepared})=>{
   assert.deepEqual(prepared,{threadId:'existing-thread',cwd:'/project'});
   sends++;
   return{threadId:prepared!.threadId,turnId:'turn-1'};
  });
  assert.deepEqual(await restarted.create(b),{id:'codex:existing-thread',nativeId:'existing-thread',turnId:'turn-1'});
  await restarted.create(b);
  assert.equal(sends,1);
 }finally{rmSync(root,{recursive:true,force:true})}
});

test('桌面未提交重试不会复用其他目录的会话，未知结果不能再次提交',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-create-retry-'));
 try{
  let calls=0;
  const b={requestId:'request-123456',prompt:'first',cwd:'/old-project'};
  const creation=new DesktopCreator(root,undefined,async(_,{prepared,savePrepared})=>{
   assert.equal(prepared,undefined);
   if(++calls===1){
    savePrepared('existing-thread');
    throw createNotSubmitted(Error('未收到桌面快照'));
   }
   throw Error('首条提交后连接断开');
  });
  await assert.rejects(creation.create(b),{outcome:'failed'});
  await assert.rejects(creation.create({...b,cwd:'/new-project'}),/连接断开/);
  await assert.rejects(creation.create(b),/结果未知/);
  assert.equal(calls,2);
 }finally{rmSync(root,{recursive:true,force:true})}
});
