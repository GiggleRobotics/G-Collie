// Route integration fixture: no model, real user home, or desktop is accessed.
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
const root=mkdtempSync(join(tmpdir(),'gcollie-headless-http-')),home=join(root,'home'),data=join(root,'data'),bin=join(root,'codex');mkdirSync(home);mkdirSync(data);writeFileSync(join(data,'hermes-ledger.json'),JSON.stringify({'fakehermes:unknown-http':{state:'unknown'}}));
writeFileSync(bin,`#!${process.execPath}
const readline=require('node:readline');let turn=0;const thread={id:'headless-qa',status:{type:'idle'},turns:[],model:'qa-model'};
readline.createInterface({input:process.stdin}).on('line',line=>{const m=JSON.parse(line);if(m.id===undefined||!m.method)return;let result={};
if(['thread/start','turn/start'].includes(m.method))require('node:fs').appendFileSync(${JSON.stringify(join(root,'creates.log'))},m.method+'\\n');
if(['thread/start','thread/read','thread/resume'].includes(m.method))result={thread,model:'qa-model'};
if(m.method==='turn/start'){const t={id:'turn-'+ ++turn,status:'inProgress',items:[]};thread.turns=[t];thread.status={type:'active',activeFlags:[]};result={turn:t}}
if(m.method==='turn/steer')result={turnId:thread.turns.at(-1).id};
if(m.method==='turn/interrupt'){thread.turns.at(-1).status='interrupted';thread.status={type:'idle'}}
if(m.method==='collaborationMode/list')result={data:[{mode:'default'},{mode:'plan'}]};
if(m.method==='plugin/installed')result={marketplaces:[]};
process.stdout.write(JSON.stringify({id:m.id,result})+'\\n');});
`,{mode:0o700});
const port=18543,base=`http://127.0.0.1:${port}`;
const child=spawn(process.execPath,['--import','tsx','server/index.ts'],{cwd:resolve('.'),env:{...process.env,HOME:home,CODEX_HOME:join(home,'.codex'),NODE_ENV:'production',HOST:'127.0.0.1',PORT:String(port),GCOLLIE_DATA_DIR:data,ORBIT_CODEX_BACKEND:'app-server',ORBIT_DESKTOP_CONTROL:'1',ORBIT_CODEX_BIN:bin,GCOLLIE_NETWORK_BINARY:'/bin/false',GCOLLIE_CLAUDE_BIN:'/bin/false'},stdio:['ignore','pipe','pipe']});let logs='';child.stdout.on('data',b=>logs+=b);child.stderr.on('data',b=>logs+=b);
try{
 for(let i=0;i<100&&!logs.includes('listening on');i++){if(child.exitCode!==null)throw Error(logs);await new Promise(r=>setTimeout(r,100))}
 assert.match(logs,/listening on/);const token=readFileSync(join(data,'access-token'),'utf8').trim();
 const api=async(path,body)=>{const response=await fetch(base+'/api'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+token,...(body!==undefined?{'Content-Type':'application/json'}:{})},body:body===undefined?undefined:JSON.stringify(body)});return{status:response.status,body:await response.json()}};
 const expectedVersion=JSON.parse(readFileSync('package.json','utf8')).version;
 const health=await fetch(base+'/healthz');assert.equal(health.status,200);assert.deepEqual(await health.json(),{ok:true,version:expectedVersion});
 const system=await api('/diagnostics/system');assert.equal(system.body.version,expectedVersion);assert.equal(system.body.codex.backend,'app-server');assert.equal(system.body.codex.available,true);
 const hermesUnknown=await api('/hermes/fakehermes',{action:'send',requestId:'unknown-http',text:'must not resend'});assert.equal(hermesUnknown.status,409);assert.equal(hermesUnknown.body.code,'hermes_result_unknown');assert.equal(hermesUnknown.body.outcome,'unknown');
 const creation={agent:'Codex',requestId:'headless-http-new',draftId:'draft:headless-http-new',prompt:'QA first',cwd:''};
 // The PNG header passes upload validation, but the truncated image cannot be decoded.
 const image=await api('/attachments',{session:creation.draftId,name:'truncated.png',image:true,data:'iVBORw0KGgo='});
 assert.equal(image.status,200);
 const rejected=await api('/sessions',{...creation,attachments:[image.body.id]});
 assert.equal(rejected.status,409);
 const imageFailure={error:'图片无法读取，请移除或更换。',code:'session_create_invalid_image',attachmentId:image.body.id};
 assert.deepEqual(rejected.body,{...imageFailure,outcome:'failed'});
 const receiptPath='/sessions/requests/'+creation.requestId;
 assert.deepEqual((await api(receiptPath)).body,{state:'failed',...imageFailure});
 assert.equal(existsSync(join(root,'creates.log')),false);
 const created=await api('/sessions',creation);assert.equal(created.status,200);assert.equal(created.body.id,'codex:headless-qa');assert.deepEqual((await api('/sessions',creation)).body,created.body);
 assert.deepEqual((await api(receiptPath)).body,{state:'done',result:created.body});
 assert.deepEqual(readFileSync(join(root,'creates.log'),'utf8').trim().split('\n'),['thread/start','turn/start']);
 const detail=await api('/local/codex:headless-qa');assert.equal(detail.status,200);assert.equal(detail.body.desktopLive,true);assert.equal(detail.body.desktopControl,true);assert.equal(detail.body.status,'running');
 const send=await api('/desktop/headless-qa',{action:'send',text:'QA steer',requestId:'headless-http-send'});assert.equal(send.status,200);assert.equal(send.body.turnId,'turn-1');
 assert.equal((await api('/desktop/headless-qa',{action:'stop',turnId:'stale',requestId:'headless-http-stale'})).status,409);
 assert.equal((await api('/desktop/headless-qa',{action:'stop',turnId:'turn-1',requestId:'headless-http-stop'})).status,200);
 const activate=await api('/local/codex:headless-qa/activate',{});assert.equal(activate.status,200);assert.equal(activate.body.status,'idle');
 const capabilities=await api('/local/codex:headless-qa/codex-capabilities');assert.equal(capabilities.status,200);assert.deepEqual(capabilities.body.modes.data.data.map(m=>m.mode),['default']);
 assert.equal((await api('/local/codex:headless-qa/mode',{mode:'plan'})).status,409);
 assert.ok((await api('/local')).body.sessions.some(s=>s.id==='codex:headless-qa'));
 console.log('PASS headless HTTP fixture: diagnostic, first-send/idempotency, live detail, steer, stale stop, stop, activate, capability truth, list');
}finally{if(child.exitCode===null){const ended=new Promise(r=>child.once('exit',r));child.kill('SIGTERM');await ended}rmSync(root,{recursive:true,force:true})}
