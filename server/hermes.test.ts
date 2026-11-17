import{test}from'node:test';import assert from'node:assert/strict';import{HermesBridge,mergeHermesDetail,hermesPending,hermesAnswer,hermesManagePatch}from'./hermes.js';import{mkdtempSync,rmSync,writeFileSync}from'node:fs';import{join}from'node:path';import{tmpdir}from'node:os';
test('Hermes operation outcome exposes only persisted status and distinguishes preflight from submitted errors',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-hermes-outcome-'));
 try{writeFileSync(join(root,'hermes-ledger.json'),JSON.stringify({'key:done12345':{state:'done',result:{private:'never expose'}},'key:pending123':{state:'sending'},'key:unknown123':{state:'unknown'}}));
 const bridge:any=new HermesBridge(root,()=>{});
 assert.equal(bridge.operationOutcome('key','done12345'),'done');assert.equal(bridge.operationOutcome('key','pending123'),'unknown');assert.equal(bridge.operationOutcome('key','unknown123'),'unknown');assert.equal(bridge.operationOutcome('key',undefined),undefined);
 bridge.connect=async()=>{};bridge.snapshot=async()=>({row:{id:'runtime'},raw:{running:false}});bridge.rpc=async()=>{throw Error('native rejection without outcome wording')};
 await assert.rejects(bridge.action('key',{action:'stop',requestId:'preflight123',turnId:'old'}));assert.equal(bridge.operationOutcome('key','preflight123'),undefined);
 await assert.rejects(bridge.action('key',{action:'send',requestId:'submitted123',text:'QA'}),/native rejection/);assert.equal(bridge.operationOutcome('key','submitted123'),'unknown');
 const restored=new HermesBridge(root,()=>{});assert.equal(restored.operationOutcome('key','submitted123'),'unknown');restored.close();bridge.close();
 }finally{rmSync(root,{recursive:true,force:true})}
});
test('Hermes 批准一次与拒绝遵循原生选项，不暴露额外上下文',()=>{const raw={open_requests:[{id:'req',method:'approval',params:{command:'printf test',choices:['once','deny'],secret:'hidden'}}]};const p=hermesPending(raw)!;assert.equal(p.kind,'approval');assert.equal((p.params as any).secret,undefined);assert.deepEqual(hermesAnswer(raw,{pendingId:'req',decision:'accept'}),{id:'req',result:{choice:'once'}});assert.throws(()=>hermesAnswer({open_requests:[]},{pendingId:'req',decision:'accept'}),/过期/)});
test('Hermes 单题和批量问题保持响应协议，多选数组协议',()=>{const single={open_requests:[{id:'q',method:'clarify',params:{question:'颜色',choices:['蓝','绿']}}]};assert.equal(hermesPending(single)?.params.questions?.[0].options[0].label,'蓝');assert.deepEqual(hermesAnswer(single,{pendingId:'q',answers:{answer:'蓝'}}),{id:'q',result:{answer:'蓝'}});const batch={open_requests:[{id:'b',method:'clarify',params:{questions:[{qid:'one',question:'问题'}]}}]};assert.throws(()=>hermesAnswer(batch,{pendingId:'b',answers:{}}));assert.deepEqual(hermesAnswer(batch,{pendingId:'b',answers:{one:'回答'}}).result,{answers:{one:'回答'}});assert.equal(hermesPending({open_requests:[{id:'m',method:'clarify',params:{multi_select:true}}]})?.params.questions?.[0].multiSelect,true)});
test('Hermes 过期停止不会调用 interrupt；未知操作结果不重放',async()=>{const root=mkdtempSync(join(tmpdir(),'orbit-hermes-'));try{writeFileSync(join(root,'hermes-ledger.json'),JSON.stringify({'key:unknown123':{state:'unknown'}}));const b:any=new HermesBridge(root,()=>{});let calls=0;b.connect=async()=>{};b.snapshot=async()=>({row:{id:'runtime'},raw:{running:true,turn_started_at:123}});b.rpc=async()=>{calls++;return{}};await assert.rejects(b.action('key',{action:'stop',requestId:'stale1234',turnId:'122'}),/轮次/);await assert.rejects(b.action('key',{action:'send',requestId:'unknown123',text:'never replay'}),/不重复/);assert.equal(calls,0);b.close()}finally{rmSync(root,{recursive:true,force:true})}});
test('会话改名与归档只提交白名单字段，拒绝空标题、超长标题与未知操作',()=>{const id='abcdefgh12345678';assert.deepEqual(hermesManagePatch({action:'rename',title:'  新名字  ',requestId:id}),{title:'新名字'});assert.deepEqual(hermesManagePatch({action:'archive',requestId:id}),{hidden:true});assert.throws(()=>hermesManagePatch({action:'rename',title:'   ',requestId:id}),/1–100/);assert.throws(()=>hermesManagePatch({action:'rename',title:'x'.repeat(101),requestId:id}),/1–100/);assert.throws(()=>hermesManagePatch({action:'send',requestId:id}),/未知操作/);assert.throws(()=>hermesManagePatch({action:'archive',requestId:'short'}),/操作编号/)});
test('Hermes 执行中仍提交 prompt.submit，沿用后端的 steer/queue/interrupt 设置',async()=>{
 const root=mkdtempSync(join(tmpdir(),'gcollie-hermes-send-'));
 try{const b:any=new HermesBridge(root,()=>{});const calls:any[]=[];
 b.connect=async()=>{};b.snapshot=async()=>({row:{id:'runtime'},raw:{running:true,turn_started_at:123}});
 b.rpc=async(method:string,params:any)=>{calls.push({method,params});return{status:'steered'}};
 await b.action('key',{action:'send',text:'补充要求',requestId:'running-send'});
 assert.deepEqual(calls,[{method:'prompt.submit',params:{session_id:'runtime',text:'补充要求'}}]);b.close();
 }finally{rmSync(root,{recursive:true,force:true})}
});

test('Hermes sudo and secret use masked input protocol and explicit cancellation',()=>{
 for(const method of ['sudo','secret']){
  const raw={open_requests:[{id:'secure',method,params:{command:'sudo true',prompt:'请输入密钥',env_var:'TEST_KEY'}}]};
  assert.equal(hermesPending(raw)?.kind,'secret');
  assert.deepEqual(hermesAnswer(raw,{pendingId:'secure',value:'test-value'}),{id:'secure',result:{value:'test-value'}});
  assert.deepEqual(hermesAnswer(raw,{pendingId:'secure',value:''}),{id:'secure',result:{value:''}});
  assert.throws(()=>hermesAnswer(raw,{pendingId:'old',value:'test-value'}),/过期/);
 }
});

test('Hermes 多选校验并序列化为原生字符串',()=>{const raw={open_requests:[{id:'m',method:'clarify',params:{multi_select:true}}]};assert.deepEqual(hermesAnswer(raw,{pendingId:'m',answers:{answer:'["蓝","绿"]'}}).result,{answer:'["蓝","绿"]'});for(const value of ['[]','bad','["蓝","蓝"]'])assert.throws(()=>hermesAnswer(raw,{pendingId:'m',answers:{answer:value}}))});

test('Hermes compaction history and cumulative live text render once within current turn',()=>{
 const events=[{id:'old',role:'assistant',text:'same',time:100},{id:'u',role:'user',text:'prompt',time:10000},{id:'a',role:'assistant',text:'same',time:11000}];
 const d=mergeHermesDetail({events},{turnId:'10',liveInflight:{user:'prompt',assistant:'same next'}});
 assert.deepEqual(d.events.map((e:any)=>e.text),['same','prompt','same',' next']);
 assert.equal(d.liveInflight.assistant,undefined);
 const committed=mergeHermesDetail({events},{turnId:'10',liveInflight:{user:'prompt',assistant:'sam'}});
 assert.equal(committed.events.length,3);
 assert.deepEqual(events.map(e=>e.text),['same','prompt','same']);
});
test('Hermes corrections keep sealed output before new input; repeated intentional user text survives',()=>{
 const events=[{id:'u1',role:'user',text:'again',time:10000},{id:'u2',role:'user',text:'again',time:12000}];
 const live={turnId:'10',liveInflight:{user:'again',assistant:'oldnew',corrections:['again'],correction_offsets:[3]}};
 const d=mergeHermesDetail({events},live);
 assert.deepEqual(d.events.map((e:any)=>e.text),['again','old','again','new']);
 assert.equal(new Set(d.events.map((e:any)=>e.id)).size,4);
 assert.deepEqual(mergeHermesDetail({events},live),d);
});
test('Hermes unanchored live snapshot is retained instead of matching historical equal text',()=>{
 const events=[{id:'old',role:'user',text:'prompt',time:1},{id:'oldreply',role:'assistant',text:'same',time:2}];
 const d=mergeHermesDetail({events},{turnId:'10',liveInflight:{user:'prompt',assistant:'same'}});
 assert.equal(d.liveInflight.assistant,'same');assert.equal(d.events.length,2);
});

test('Hermes correction boundaries use Unicode code points and do not split emoji',()=>{
 const events=[{id:'u1',role:'user',text:'one',time:10000},{id:'u2',role:'user',text:'two',time:11000}];
 const d=mergeHermesDetail({events},{turnId:'10',liveInflight:{user:'one',assistant:'好😀后续',corrections:['two'],correction_offsets:[2]}});
 assert.deepEqual(d.events.map((e:any)=>e.text),['one','好😀','two','后续']);
});

test('Hermes private gateway grants bind the exact origin/profile and mint each purpose separately',async()=>{
 const {hermesGatewayTicket}=await import('./hermes.js');const {createServer}=await import('node:net');const {chmodSync}=await import('node:fs');
 const home=mkdtempSync(join(tmpdir(),'hc-'));const purposes:string[]=[];
 const server=createServer(c=>{let data='';c.on('data',chunk=>{data+=chunk;if(!data.includes('\n'))return;const q=JSON.parse(data.split('\n')[0]);const result=q.verb==='identify'?{runtime_protocol:1,instance_id:'instance',api_origin:'http://127.0.0.1:9876',served_profiles:[{home,profile_id:'profile'}]}:(purposes.push(q.params.purpose),assert.equal(q.params.profile_id,'profile'),assert.equal(q.params.instance_id,'instance'),{ticket:'one-time-grant-12345678'});c.end(JSON.stringify({protocol:1,id:1,ok:true,result})+'\n')})});
 await new Promise<void>(r=>server.listen(join(home,'gateway.sock'),r));chmodSync(join(home,'gateway.sock'),0o600);
 try{assert.equal(await hermesGatewayTicket('http://127.0.0.1:9876','interactive',home),'one-time-grant-12345678');await hermesGatewayTicket('http://127.0.0.1:9876','native-http',home);assert.deepEqual(purposes,['interactive','native-http']);await assert.rejects(hermesGatewayTicket('http://127.0.0.1:9877','interactive',home),/不匹配/);chmodSync(join(home,'gateway.sock'),0o666);await assert.rejects(hermesGatewayTicket('http://127.0.0.1:9876','interactive',home),/权限不安全/)}finally{await new Promise<void>(r=>server.close(()=>r()));rmSync(home,{recursive:true,force:true})}
});

test('Hermes malformed discovery or missing profile never requests a gateway grant',async()=>{
 const {hermesGatewayTicket}=await import('./hermes.js');const {createServer}=await import('node:net');const {chmodSync}=await import('node:fs');
 for(const identity of [null,{runtime_protocol:1,instance_id:'i',api_origin:'http://127.0.0.1:9876',served_profiles:[]},{runtime_protocol:1,instance_id:'i',api_origin:'http://127.0.0.1:9876',served_profiles:[{home:'/other-user',profile_id:'p'}]}]){
  const home=mkdtempSync(join(tmpdir(),'hc-'));let grants=0;
  const server=createServer(c=>c.once('data',raw=>{const q=JSON.parse(raw.toString());if(q.verb!=='identify')grants++;c.end(identity===null?'invalid\n':JSON.stringify({protocol:1,id:1,ok:true,result:identity})+'\n')}));
  await new Promise<void>(r=>server.listen(join(home,'gateway.sock'),r));chmodSync(join(home,'gateway.sock'),0o600);
  try{await assert.rejects(hermesGatewayTicket('http://127.0.0.1:9876','interactive',home));assert.equal(grants,0)}finally{await new Promise<void>(r=>server.close(()=>r()));rmSync(home,{recursive:true,force:true})}
 }
});

test('Hermes login-required backends are rejected before HTML or native credential discovery',async()=>{
 const original=globalThis.fetch;const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});let calls=0;
 bridge.discover=async()=> 'http://127.0.0.1:9876';globalThis.fetch=async()=>{calls++;return new Response(JSON.stringify({auth_required:true}))};
 try{await assert.rejects(bridge.active(),/要求登录/);assert.equal(calls,1)}finally{globalThis.fetch=original;bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes legacy HTML credential still opens its token-authenticated socket',async()=>{
 const originalFetch=globalThis.fetch,originalSocket=globalThis.WebSocket;const root=mkdtempSync(join(tmpdir(),'hc-'));const urls:string[]=[];
 class FakeSocket{static OPEN=1;readyState=1;onopen?:()=>void;onmessage?:(v:any)=>void;onclose?:()=>void;onerror?:()=>void;constructor(url:string,protocols?:string[]){urls.push(url);assert.equal(protocols,undefined);queueMicrotask(()=>this.onopen?.())}send(value:string){const r=JSON.parse(value);queueMicrotask(()=>this.onmessage?.({data:JSON.stringify({id:r.id,result:r.method==='session.active_list'?{sessions:[]}: {}})}))}close(){this.readyState=3;this.onclose?.()}}
 globalThis.WebSocket=FakeSocket as any;globalThis.fetch=async(input:any)=>String(input).endsWith('/api/status')?new Response(JSON.stringify({auth_required:false})):new Response('<script>window.__HERMES_SESSION_TOKEN__="legacy-fixture-token";</script>');const bridge:any=new HermesBridge(root,()=>{});bridge.discover=async()=> 'http://127.0.0.1:9876';
 try{assert.deepEqual(await bridge.active(),[]);assert.deepEqual(urls,['ws://127.0.0.1:9876/api/ws?token=legacy-fixture-token'])}finally{bridge.close();globalThis.fetch=originalFetch;globalThis.WebSocket=originalSocket;rmSync(root,{recursive:true,force:true})}
});

test('Hermes gateway snapshot and approval mapping preserve generation fences and reject unknown requests',async()=>{
 const {hermesGatewaySnapshot,hermesGatewayAnswer}=await import('./hermes.js');
 const raw=hermesGatewaySnapshot({running:true,execution_generation:7,prompts:[{kind:'approval',prompt_id:'p',execution_generation:7,choices:['once','deny'],command:'fixture'},{kind:'clarify',prompt_id:'q',execution_generation:7,question:'choose',choices:['a','b']}],open_requests:[{id:'srq-secret',method:'secret',params:{prompt:'fixture'}}]});
 assert.equal(raw.turn_started_at,7);assert.equal(hermesPending(raw)?.kind,'approval');assert.deepEqual(hermesGatewayAnswer(raw,{pendingId:'p',decision:'accept'},'session'),{method:'approval.respond',params:{session_id:'session',execution_generation:7,prompt_id:'p',choice:'once'}});
 assert.deepEqual(hermesGatewayAnswer(raw,{pendingId:'q',answers:{answer:'a'}},'session'),{method:'clarify.respond',params:{session_id:'session',execution_generation:7,prompt_id:'q',answer:'a'}});
 assert.equal(hermesPending({...raw,open_requests:[raw.open_requests[2]]})?.kind,'secret');assert.throws(()=>hermesGatewayAnswer(raw,{pendingId:'srq-secret',value:'never-transmitted'},'session'),/电脑处理/);assert.throws(()=>hermesGatewaySnapshot({running:true}),/不受支持/);
});

test('Hermes gateway pure view reads generation and replay prompts without resume; actions fence stop and approvals',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};const calls:any[]=[];let running=true;const prompt={kind:'approval',prompt_id:'p',execution_generation:9,choices:['once','deny'],command:'fixture'};
 bridge.active=async()=>[{id:'session',session_key:'key',status:running?'working':'idle'}];bridge.gatewayMetadata=async()=>({id:'session',runtime_generation:9});
 bridge.rpc=async(method:string,params:any)=>{calls.push({method,params});if(method==='session.activate')return{session_id:'session',session_key:'key'};if(method==='session.events.since')return{replay_epoch:'epoch',last_sequence:1,snapshot_required:false,open_requests:[],events:[{session_id:'session',execution_generation:9,type:'approval.request',payload:prompt}]};return{status:'resolved'}};
 try{const d=await bridge.view('key');assert.equal(d.hermesLive,true);assert.equal(d.readOnly,false);assert.equal(d.turnId,'9');assert.equal(d.pending.kind,'approval');assert.equal(d.pending.generation,9);assert.equal(d.pending.requestEpoch,'epoch');assert.equal(calls.some(c=>c.method==='session.resume'),false);
 await bridge.action('key',{action:'send',requestId:'fixture-send',text:'append'});assert.deepEqual(calls.find(c=>c.method==='prompt.submit')?.params,{session_id:'session',text:'append',submission_id:'fixture-send'});
 await bridge.action('key',{action:'stop',requestId:'fixture-stop',turnId:'9'});assert.deepEqual(calls.find(c=>c.method==='session.interrupt')?.params,{session_id:'session',execution_generation:9});await assert.rejects(bridge.action('key',{action:'stop',requestId:'fixture-stale',turnId:'8'}),/轮次/);
 await bridge.action('key',{action:'answer',requestId:'fixture-approve',pendingId:'p',decision:'accept',expectedGeneration:9,requestEpoch:'epoch'});assert.deepEqual(calls.find(c=>c.method==='approval.respond')?.params,{session_id:'session',execution_generation:9,prompt_id:'p',choice:'once'});await assert.rejects(bridge.action('key',{action:'answer',requestId:'fixture-old-answer',pendingId:'p',decision:'accept',expectedGeneration:8}),/轮次/);assert.equal(calls.filter(c=>c.method==='approval.respond').length,1);assert.equal(calls.some(c=>c.method==='session.resume'),false);
 }finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes gateway create normalizes identity; load only activates an existing live runtime',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};let rows:any[]=[];bridge.active=async()=>rows;bridge.readGateway=async(id:string,row:any)=>{assert.equal(id,'runtime');assert.equal(row.status,'working');return{}};const calls:any[]=[];
 bridge.rpc=async(method:string,params:any)=>{calls.push({method,params});if(method==='session.create')return{session_id:'native-session'};if(method==='session.activate'){rows=[{id:'runtime',session_key:'native-session',status:'working'}];return{session_id:'runtime',session_key:'native-session'}};throw Error('unexpected '+method)};
 try{assert.equal((await bridge.create({requestId:'fixture-create',title:'fixture',cwd:'/tmp'})).session_key,'native-session');assert.deepEqual(calls[0],{method:'session.create',params:{source:'gui',request_id:'fixture-create',title:'fixture',cwd:'/tmp'}});
 await assert.rejects(bridge.load('native-session'),/原子恢复/);assert.equal(calls.length,1);
 rows=[{id:'runtime',session_key:'native-session',status:'idle'}];assert.equal(await bridge.load('native-session'),'native-session');assert.deepEqual(calls[1],{method:'session.activate',params:{session_id:'runtime',omit_messages:true}});
 }finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes live attach refuses a changed runtime and never falls back to resume',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;let reads=0;bridge.active=async()=>[{id:++reads===1?'runtime':'replacement',session_key:'key',status:'idle'}];const calls:string[]=[];bridge.rpc=async(method:string)=>{calls.push(method);return{session_id:'runtime',session_key:'key'}};
 try{await assert.rejects(bridge.snapshot('key',true),/运行实例已变化/);assert.deepEqual(calls,['session.activate']);
 reads=0;bridge.rpc=async(method:string)=>{calls.push(method);return{session_id:'other',session_key:'key'}};await assert.rejects(bridge.snapshot('key',true),/附着会话已变化/);
 }finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes incomplete replay rejects approval and private answers before submission',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};let calls=0;bridge.rpc=async()=>{calls++;return{}};
 try{for(const complete of [false,undefined]){bridge.snapshot=async()=>({row:{id:'runtime'},raw:{replayComplete:complete,execution_generation:9,replay_epoch:'epoch',prompts:[{prompt_id:'p',kind:'approval',execution_generation:9,choices:['once','deny']}],open_requests:[{id:'srq-secret',method:'secret',params:{}}]}});
 for(const pendingId of ['p','srq-secret']){const requestId='fixture-'+pendingId;await assert.rejects(bridge.action('key',{action:'answer',requestId,pendingId,decision:'accept',value:'synthetic',expectedGeneration:9,requestEpoch:'epoch'}),/记录不完整/);assert.equal(bridge.operationOutcome('key',requestId),undefined)}}assert.equal(calls,0);
 }finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes gateway stages images and submits only native path/mime references with the original submission ID',async()=>{
 const {readFileSync}=await import('node:fs');const {repairCachedImage}=await import('./claude-media.js');const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};bridge.snapshot=async()=>({row:{id:'session'},raw:{running:true,execution_generation:4}});writeFileSync(join(root,'fixture.jpg'),Buffer.concat([Buffer.from('P6\n16 16\n255\n'),Buffer.alloc(16*16*3,255)]));await repairCachedImage(join(root,'fixture.jpg'));const stagedBytes=readFileSync(join(root,'media/image.jpg'));const calls:any[]=[];
 bridge.rpc=async(method:string,params:any)=>{calls.push({method,params});return method==='image.attach_bytes'?{attached:true,path:'/fixture/cache/images/staged.jpg',mime:'image/jpeg'}:{status:'queued'}};
 try{await bridge.action('key',{action:'send',requestId:'fixture-media',text:'see image',attachments:[{id:'image',name:'fixture.jpg',path:join(root,'fixture.jpg'),image:true,mime:'image/jpeg'}]});assert.equal(calls[0].method,'image.attach_bytes');assert.deepEqual(Buffer.from(calls[0].params.content_base64,'base64'),stagedBytes);assert.deepEqual([...stagedBytes.subarray(0,3)],[255,216,255]);assert.deepEqual(calls[1].params.attachments,[{path:'/fixture/cache/images/staged.jpg',mime:'image/jpeg'}]);assert.equal(calls[1].params.submission_id,'fixture-media');assert.equal(readFileSync(join(root,'hermes-ledger.json'),'utf8').includes(calls[0].params.content_base64),false)}finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes gateway private answers and cancellation require an observed consumption receipt and never persist values',async()=>{
 const {readFileSync}=await import('node:fs');for(const method of ['sudo','secret','clarify']){
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};let consumed=false;const frames:any[]=[];const request={id:'srq-fixture',method,params:method==='clarify'?{question:'fixture'}:{prompt:'fixture'}};
 bridge.snapshot=async()=>({row:{id:'session'},raw:{replayComplete:true,running:true,execution_generation:4,replay_epoch:'epoch',prompts:[],open_requests:[request]}});bridge.socket={readyState:WebSocket.OPEN,send:(text:string)=>{frames.push(JSON.parse(text));consumed=true},close:()=>{}};
 bridge.rpc=async()=>({replay_epoch:'epoch',open_requests:consumed?[]:[request]});
 try{const value=method==='sudo'?'':'fixture-private-value';const result=await bridge.action('key',{action:'answer',requestId:'fixture-private',pendingId:request.id,expectedGeneration:4,requestEpoch:'epoch',value,answers:{answer:'fixture-answer'}});assert.equal(result.status,'resolved');assert.equal(frames.length,1);assert.equal(frames[0].method,undefined);assert.equal(frames[0].id,request.id);if(method!=='clarify')assert.equal(frames[0].result.value,value);assert.equal(readFileSync(join(root,'hermes-ledger.json'),'utf8').includes('fixture-private-value'),false);await bridge.action('key',{action:'answer',requestId:'fixture-private',pendingId:request.id,expectedGeneration:4,value});assert.equal(frames.length,1)}finally{bridge.close();rmSync(root,{recursive:true,force:true})}
 }
});

test('Hermes gateway missing private answer receipt becomes unknown and cannot be replayed',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};let sent=0;const request={id:'srq-fixture',method:'secret',params:{prompt:'fixture'}};bridge.snapshot=async()=>({row:{id:'session'},raw:{replayComplete:true,execution_generation:3,replay_epoch:'epoch',prompts:[],open_requests:[request]}});bridge.socket={readyState:WebSocket.OPEN,send:()=>{sent++},close:()=>{}};bridge.rpc=async()=>({replay_epoch:'epoch',open_requests:[request]});
 try{await assert.rejects(bridge.action('key',{action:'answer',requestId:'fixture-unknown-private',pendingId:request.id,expectedGeneration:3,requestEpoch:'epoch',value:'fixture-value'}),/结果未知/);await assert.rejects(bridge.action('key',{action:'answer',requestId:'fixture-unknown-private',pendingId:request.id,expectedGeneration:3,requestEpoch:'epoch',value:'fixture-value'}),/不重复/);await assert.rejects(bridge.action('key',{action:'answer',requestId:'fixture-new-private-id',pendingId:request.id,expectedGeneration:3,requestEpoch:'epoch',value:'fixture-value'}),/结果未知/);assert.equal(sent,1);bridge.close();const restarted:any=new HermesBridge(root,()=>{});restarted.nativeAuth=true;restarted.connect=async()=>{};restarted.snapshot=bridge.snapshot;restarted.socket=bridge.socket;try{await assert.rejects(restarted.action('key',{action:'answer',requestId:'fixture-restart-private-id',pendingId:request.id,expectedGeneration:3,requestEpoch:'epoch',value:'fixture-value'}),/结果未知/);assert.equal(sent,1)}finally{restarted.close()}}finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes approval with an explicit empty decision list cannot be accepted or declined',()=>{const raw={open_requests:[{id:'empty',method:'approval',params:{choices:[]}}]};assert.deepEqual(hermesPending(raw)?.params.availableDecisions,[]);for(const decision of ['accept','decline'])assert.throws(()=>hermesAnswer(raw,{pendingId:'empty',decision}),/未提供/)});

test('Hermes replay gaps stay unsafe after live attach until replay itself becomes complete',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};bridge.active=async()=>[{id:'session',session_key:'session',status:'working'}];bridge.gatewayMetadata=async()=>({id:'session',runtime_generation:12});let activates=0;let gap=true;const calls:string[]=[];
 bridge.rpc=async(method:string)=>{calls.push(method);if(method==='session.activate'){activates++;return{session_id:'session',session_key:'session'}}if(method==='session.events.since')return{replay_epoch:'epoch',last_sequence:20,snapshot_required:gap,events:gap?[]:[{session_id:'session',execution_generation:12,type:'approval.request',payload:{kind:'approval',prompt_id:'fresh',execution_generation:12,choices:['deny']}}],open_requests:[]};return{}};
 try{const before=await bridge.view('session');assert.equal(activates,0);assert.match(before.desktopError,/不完整/);assert.equal(before.pending,undefined);assert.equal(before.turnId,'12');await bridge.load('session');assert.equal(activates,1);assert.match((await bridge.view('session')).desktopError,/不完整/);
 gap=false;await bridge.load('session');const after=await bridge.view('session');assert.equal(activates,2);assert.equal(after.pending.id,'fresh');assert.equal(after.desktopError,undefined);assert.deepEqual(after.pending.params.availableDecisions,['decline']);assert.equal(calls.includes('session.resume'),false)}finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});

test('Hermes stale generation or request epoch never sends a private answer frame',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;bridge.connect=async()=>{};let sends=0;bridge.socket={readyState:WebSocket.OPEN,send:()=>sends++,close:()=>{}};bridge.snapshot=async()=>({row:{id:'session'},raw:{replayComplete:true,execution_generation:5,replay_epoch:'current',prompts:[],open_requests:[{id:'srq-same',method:'secret',params:{}}]}});
 try{for(const [expectedGeneration,requestEpoch] of [[4,'current'],[5,'old'],[undefined,'current'],[5,undefined]])await assert.rejects(bridge.action('session',{action:'answer',requestId:'stale-answer-'+String(expectedGeneration)+'-'+String(requestEpoch),pendingId:'srq-same',expectedGeneration,requestEpoch,value:'never transmitted'}),/变化/);assert.equal(sends,0)}finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});


test('Hermes managed bypass modes report private input capability without a false connection error',async()=>{
 const root=mkdtempSync(join(tmpdir(),'hc-'));const bridge:any=new HermesBridge(root,()=>{});bridge.nativeAuth=true;
 try{for(const launch of [{ignore_user_config:true},{safe_mode:true},{}]){bridge.snapshot=async()=>({row:{id:'session'},raw:{running:false,execution_generation:1,launch_request:launch}});const view=await bridge.view('session');assert.equal(view.gatewayCapabilities.secrets,!Object.values(launch).includes(true));assert.equal(view.gatewayCapabilities.textSend,true);assert.equal(view.desktopError,undefined)}}finally{bridge.close();rmSync(root,{recursive:true,force:true})}
});
