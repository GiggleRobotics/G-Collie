import{test}from'node:test';import assert from'node:assert/strict';import{mkdtempSync,rmSync}from'node:fs';import{tmpdir}from'node:os';import{join}from'node:path';import{DesktopCreator}from'./desktop-create.js';
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
