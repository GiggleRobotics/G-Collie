import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {spawn,execFileSync} from 'node:child_process';import assert from 'node:assert/strict';
const root=path.resolve(process.argv[2]||'.packaging/deb/usr/lib/g-collie'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'collie-full-'));const base='http://127.0.0.1:18437';const child=spawn(root+'/runtime/node',[root+'/server.mjs'],{cwd:root,env:{...process.env,NODE_ENV:'production',HOST:'127.0.0.1',PORT:'18437',GCOLLIE_DATA_DIR:dir,ORBIT_DESKTOP_CONTROL:'0'},stdio:'ignore'});
try{
 let ready=false;for(let i=0;i<100;i++){try{if((await fetch(base+'/healthz')).ok){ready=true;break}}catch{}await new Promise(r=>setTimeout(r,100))}assert.ok(ready);
 execFileSync(root+'/ffmpeg',['-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=blue:s=160x120','-frames:v','1','-y',dir+'/sample.png'],{cwd:dir,env:{...process.env,PATH:''}});
 execFileSync(root+'/ffmpeg',['-hide_banner','-loglevel','error','-nostdin','-threads','1','-i',dir+'/sample.png','-frames:v','1','-vf','scale=2048:2048:force_original_aspect_ratio=decrease','-q:v','3','-y',dir+'/sample.jpg'],{cwd:dir,env:{...process.env,PATH:''}});
 assert.equal(fs.readFileSync(dir+'/sample.jpg').subarray(0,2).toString('hex'),'ffd8');

 const token=fs.readFileSync(dir+'/access-token','utf8').trim();
 const req=async(p,body,cookie,owner=false)=>{const r=await fetch(base+p,{method:body===undefined?'GET':'POST',headers:{...(body!==undefined?{'Content-Type':'application/json'}:{}),...(cookie?{Cookie:cookie}:{}),...(owner?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});const text=await r.text();let data;try{data=JSON.parse(text)}catch{data=text}return{status:r.status,data,cookie:r.headers.get('set-cookie')?.split(';')[0]}};
 assert.equal((await req('/api/local')).status,401);assert.equal((await fetch(base+'/')).status,200);
 const invite=await req('/api/devices/pair',{origin:base},null,true);assert.equal(invite.status,200);
 const phone=await req('/api/auth/pair',{code:invite.data.code,name:'isolated-full-qa'});assert.equal(phone.status,200);assert.ok(phone.cookie);
 assert.equal((await req('/api/diagnostics/requests',undefined,phone.cookie)).status,403);
 const range={from:new Date(Date.now()-60000).toISOString(),to:new Date().toISOString()};
 const collect=await req('/api/diagnostics/requests',{...range,device:phone.data.device.id},null,true);assert.equal(collect.status,200);
 const pending=await req('/api/diagnostics/requests/pending',undefined,phone.cookie);assert.equal(pending.data.requests[0].id,collect.data.id);
 const upload=await req('/api/diagnostics/phone',{...range,requestId:collect.data.id,events:[{time:range.to,category:'qa',route:'/connection/health',password:'must-not-keep'}]},phone.cookie);assert.equal(upload.status,200);
 const bundle=await req('/api/diagnostics/bundle?'+new URLSearchParams({...range,device:phone.data.device.id}),undefined,null,true);assert.equal(bundle.status,200);assert.equal(bundle.data.phone.length,1);assert.ok(!JSON.stringify(bundle.data).includes('must-not-keep'));
 const revoked=await req('/api/devices/'+phone.data.device.id+'/revoke',{},null,true);assert.equal(revoked.status,200);assert.equal((await req('/api/diagnostics/phone',{...range,events:[]},phone.cookie)).status,401);assert.equal((await req('/api/diagnostics/requests/pending',undefined,phone.cookie)).status,401);
 console.log('PASS packaged ffmpeg photo conversion without PATH, standalone package, private data isolation, web, auth, diagnostics owner boundary, phone request/reply/export, revocation');
}finally{if(child.exitCode===null){const ended=new Promise(r=>child.once('exit',r));child.kill('SIGTERM');await ended;}fs.rmSync(dir,{recursive:true,force:true});}
