// Runs the current source server against a fresh HOME/data dir with model binaries disabled.
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
const root=mkdtempSync(join(tmpdir(),'gcollie-http-')),home=join(root,'home'),data=join(root,'data');mkdirSync(home);
// Exercise the same data sources as previously created sessions, imported Claude
// transcripts and an old managed alias, with no Agent binary or account access.
const cwd=join(root,'workspace'),ref='.packaging/qa/result.png';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mO4uZULAAQDAZlPBCu3AAAAAElFTkSuQmCC','base64');
const native='fixture-history',id='codex:'+native,alias='managed:'+native;
const fallback='hermes:created-fixture',claudeId='5885bde1-e624-4381-9af0-b744c5fb2698';
const assistant={id:'reported',role:'assistant',text:'![结果]('+ref+')',time:1};
const session={cwd,id,nativeId:native,agent:'Codex',events:[assistant],archived:true};
mkdirSync(data);
mkdirSync(join(cwd,'.packaging','qa'),{recursive:true});
writeFileSync(join(cwd,ref),png);
writeFileSync(join(data,'created-sessions.json'),JSON.stringify({
 [id]:session,[fallback]:{...session,agent:'Hermes',id:fallback,nativeId:'created-fixture',events:[{...assistant,text:'',media:[ref]}]},
}));
writeFileSync(join(data,'codex-managed.json'),JSON.stringify({sessions:[{...session,id:alias,events:[]}]}));
const transcripts=join(home,'.claude','projects','fixture');
mkdirSync(transcripts,{recursive:true});
writeFileSync(join(transcripts,claudeId+'.jsonl'),JSON.stringify({cwd,type:'assistant',uuid:'reported',message:{role:'assistant',content:assistant.text}}));
const port=18542,base=`http://127.0.0.1:${port}`;
const child=spawn(process.execPath,['--import','tsx','server/index.ts'],{cwd:resolve('.'),env:{...process.env,HOME:home,CODEX_HOME:join(home,'.codex'),XDG_CONFIG_HOME:join(home,'.config'),NODE_ENV:'production',HOST:'127.0.0.1',PORT:String(port),GCOLLIE_DATA_DIR:data,ORBIT_DESKTOP_CONTROL:'0',ORBIT_CODEX_BIN:'/bin/false',GCOLLIE_CLAUDE_BIN:'/bin/false',GCOLLIE_NETWORK_BINARY:'/bin/false'},stdio:['ignore','pipe','pipe']});
let logs='';child.stdout.on('data',b=>logs+=b);child.stderr.on('data',b=>logs+=b);
try {
 for(let i=0;i<100;i++){if(child.exitCode!==null)throw Error('isolated server failed '+logs);if(logs.includes(`listening on 127.0.0.1:${port}`))break;await new Promise(r=>setTimeout(r,100));}
 assert.match(logs,/listening on/);
 const token=readFileSync(join(data,'access-token'),'utf8').trim();
 const req=async(path,{body,cookie,owner=false,headers={}}={})=>{const r=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body!==undefined?{'Content-Type':'application/json'}:{}),...(cookie?{Cookie:cookie}:{}),...(owner?{Authorization:'Bearer '+token}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body)});let d;try{d=await r.json()}catch{}return{r,d,cookie:r.headers.get('set-cookie')?.split(';')[0]};};
 assert.equal((await req('/api/local')).r.status,401);
 const owner=await req('/api/auth/exchange',{body:{name:'isolated owner'},owner:true});assert.equal(owner.r.status,200);assert.match(owner.r.headers.get('set-cookie'),/HttpOnly/);assert.match(owner.r.headers.get('set-cookie'),/SameSite=Strict/);
 const admin={cookie:owner.cookie};
 const invite=await req('/api/devices/pair',{...admin,body:{origin:base}});assert.equal(invite.r.status,200);
 const phone=await req('/api/auth/pair',{body:{code:invite.d.code,name:'isolated phone'}});assert.equal(phone.r.status,200);
 assert.equal((await req('/api/auth/pair',{body:{code:invite.d.code,name:'replay'}})).r.status,429);
 assert.equal((await req('/api/devices',{cookie:phone.cookie})).r.status,403);
 assert.equal((await req('/api/local',{cookie:phone.cookie})).r.status,200);
 assert.equal((await req('/api/devices/pair',{...admin,body:{},headers:{Origin:'https://evil.example'}})).r.status,403);
 assert.equal((await req('/api/push/subscribe',{...admin,body:{subscription:{endpoint:'https://127.0.0.1/secret',keys:{auth:'a',p256dh:'b'}}}})).r.status,400);
 assert.equal((await req('/api/schedules',admin)).d.tasks.length,0);
 const adapters=(await req('/api/adapters',admin));assert.equal(adapters.r.status,200);assert.equal(adapters.d.length,3);assert.ok(adapters.d.every(a=>a.capabilities.history&&a.capabilities.usage&&!a.capabilities.control));assert.equal(adapters.d.find(a=>a.agent==='Codex').control.enabled,false);assert.equal(adapters.d.find(a=>a.agent==='Hermes').control.availability,'session-dependent');
 assert.equal((await req('/api/desktop/fake',{cookie:phone.cookie,body:{action:'send',text:'must not run',requestId:'isolated-test'}})).r.status,409);
 const resourceIds=new Map();
 for(const key of [id,alias,fallback,'claude:'+claudeId]){
  const path='/api/local/'+key,auth={cookie:phone.cookie};
  const detail=await req(path,auth),history=await req(path+'/history',auth),list=await req(path+'/resources',auth);
  assert.equal(detail.r.status,200,key);assert.equal(history.r.status,200,key);assert.equal(list.r.status,200,key);
  assert.equal(detail.d.id,key===alias?id:key);assert.equal(history.d.id,detail.d.id);
  assert.deepEqual(history.d.events,detail.d.events);
  const [image]=list.d.resources;assert.equal(image.ref,ref);
  resourceIds.set(key,image.id);
  const content=await fetch(base+path+'/resources/'+image.id,{headers:{Cookie:phone.cookie}});
  assert.equal(content.status,200);assert.equal(content.headers.get('content-type'),'image/png');
  assert.deepEqual(Buffer.from(await content.arrayBuffer()),png);
  const preview=await req(path+'/resources/'+image.id+'/preview',{...auth,body:{}});
  assert.equal(preview.r.status,200);
  const previewContent=await fetch(base+preview.d.path.replace('/view','/content'));
  assert.deepEqual(Buffer.from(await previewContent.arrayBuffer()),png);
 }
 assert.equal(resourceIds.get(alias),resourceIds.get(id));
 assert.notEqual(resourceIds.get(fallback),resourceIds.get(id));
 assert.equal((await req('/api/local/'+fallback+'/resources/'+resourceIds.get(id),admin)).r.status,404);
 assert.equal((await req('/api/local/managed:unregistered/resources',admin)).r.status,404);
 console.log('PASS source HTTP: created fallback, registered managed alias, native Claude, and session-bound image bytes/tickets');
 const revoked=await req('/api/devices/'+phone.d.device.id+'/revoke',{...admin,body:{}});assert.equal(revoked.r.status,200);assert.equal((await req('/api/local',{cookie:phone.cookie})).r.status,401);
 assert.equal((await req('/api/auth/logout',{...admin,body:{}})).r.status,200);assert.equal((await req('/api/local',admin)).r.status,401);
 assert.equal((await fetch(base+'/healthz')).status,200);
 console.log('PASS current source isolated HTTP: bootstrap, cookie flags, pair/replay, owner boundary, CSRF, push guard, disabled control, revoke/logout');
}finally{
 if(child.exitCode===null){const ended=new Promise(r=>child.once('exit',r));child.kill('SIGTERM');await ended;}
 rmSync(root,{recursive:true,force:true});
}
