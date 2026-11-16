import {test} from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
const launcher=resolve('scripts/installed-launcher.mjs');
async function run(args,env){return new Promise(resolve=>{const p=spawn(process.execPath,[launcher,'pair',...args],{env:{...process.env,...env}});let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);p.on('close',code=>resolve({code,out,err}));});}
test('terminal pairing authenticates locally, prints only short-lived invite, and preserves remote origin',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'gcollie-pair-'));const key='PRIVATE_OWNER_KEY_FOR_TEST';await writeFile(join(dir,'access-token'),key);let invites=0;
 const server=http.createServer((req,res)=>{assert.equal(req.socket.remoteAddress,'127.0.0.1');assert.equal(req.headers.authorization,'Bearer '+key);assert.match(req.headers.host,/^127\.0\.0\.1:/);res.setHeader('Content-Type','application/json');
 if(req.url==='/api/network')res.end(JSON.stringify({embedded:{address:'http://100.100.100.100:4310'}}));
 else if(req.url==='/api/devices/pair'&&req.method==='POST'){invites++;res.end(JSON.stringify({code:'123456',url:'http://127.0.0.1:4310/#pair=SHORT_LIVED_INVITE',expiresAt:Date.now()+600000}));}
 else {res.statusCode=404;res.end('{}');}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{const result=await run([`http://127.0.0.1:${server.address().port}`,'--json'],{GCOLLIE_DATA_DIR:dir});assert.equal(result.code,0,result.err);const p=JSON.parse(result.out);assert.equal(p.code,'123456');assert.equal(p.url,'http://100.100.100.100:4310/#pair=SHORT_LIVED_INVITE');assert.ok(!result.out.includes(key));assert.equal(invites,1);
 const bad=await run(['http://192.0.2.1:4310'],{GCOLLIE_DATA_DIR:dir});assert.equal(bad.code,1);assert.match(bad.err,/本机/);assert.equal(invites,1);assert.ok(!bad.err.includes(key));
 const credential=await run(['http://user:password@127.0.0.1:4310'],{GCOLLIE_DATA_DIR:dir});assert.equal(credential.code,1);assert.equal(invites,1);
 }finally{await new Promise(r=>server.close(r));await rm(dir,{recursive:true,force:true});}
});
test('missing owner state fails without starting service or disclosing secrets',async()=>{const dir=await mkdtemp(join(tmpdir(),'gcollie-pair-'));try{const r=await run([],{GCOLLIE_DATA_DIR:dir});assert.equal(r.code,1);assert.match(r.err,/生成配对码失败/);assert.equal(r.out,'');}finally{await rm(dir,{recursive:true,force:true});}});
