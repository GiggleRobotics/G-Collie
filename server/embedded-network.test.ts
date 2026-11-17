import{test}from'node:test';import assert from'node:assert/strict';import{mkdtemp,writeFile,readFile,rm}from'node:fs/promises';import{join}from'node:path';import{tmpdir}from'node:os';import{EmbeddedNetwork,embeddedNetworkEnvironment}from'./embedded-network.js';
async function until(check:()=>boolean){for(let i=0;i<60;i++){if(check())return;await new Promise(r=>setTimeout(r,25))}assert.fail('network state did not arrive')}
test('内置网络生命周期独立：关闭进程保留启用意图，显式停止才取消恢复；公开状态不泄漏登录入口',async()=>{const dir=await mkdtemp(join(tmpdir(),'gcollie-net-'));const binary=join(dir,'stub');await writeFile(binary,`#!/usr/bin/env node\nprocess.stdout.write(JSON.stringify({state:'NeedsLogin',authURL:'https://login.tailscale.com/a/test'})+'\\n');require('node:readline').createInterface({input:process.stdin}).on('line',line=>{const c=JSON.parse(line);if(c.action==='login')console.log(JSON.stringify({state:'Running',address:'http://100.100.1.2:4310'}))});`,{mode:0o700});let network=new EmbeddedNetwork(dir,4310,binary);try{await network.start();await until(()=>network.status().state==='NeedsLogin');assert.ok(network.status().authURL);assert.equal('authURL'in network.publicStatus(),false);network.login();await until(()=>!!network.publicStatus().address);network.close();assert.equal(JSON.parse(await readFile(join(dir,'network-enabled.json'),'utf8')).enabled,true);network=new EmbeddedNetwork(dir,4310,binary);await network.restore();await until(()=>network.status().state==='NeedsLogin');network.stop();assert.equal(JSON.parse(await readFile(join(dir,'network-enabled.json'),'utf8')).enabled,false)}finally{network.close();await rm(dir,{recursive:true,force:true})}});
test('未安装内置模块明确拒绝启动，不修改启用状态',async()=>{const dir=await mkdtemp(join(tmpdir(),'gcollie-net-'));const network=new EmbeddedNetwork(dir,4310,join(dir,'missing'));try{assert.equal(network.status().available,false);await assert.rejects(()=>network.start(),/未包含内置网络模块/);assert.equal(network.status().state,'Stopped')}finally{network.close();await rm(dir,{recursive:true,force:true})}});
test('网络进程意外退出自动恢复，显式停止后不再重启',async()=>{const dir=await mkdtemp(join(tmpdir(),'gcollie-net-'));const binary=join(dir,'stub');await writeFile(binary,`#!/usr/bin/env node\nconst fs=require('node:fs'),p=__dirname+'/attempts';const n=fs.existsSync(p)?Number(fs.readFileSync(p)):0;fs.writeFileSync(p,String(n+1));if(n===0)process.exit(1);console.log(JSON.stringify({state:'Running',address:'http://100.100.1.2:4310'}));setInterval(()=>{},1000);`,{mode:0o700});const network=new EmbeddedNetwork(dir,4310,binary);try{await network.start();await until(()=>network.status().state==='Running');assert.equal(await readFile(join(dir,'attempts'),'utf8'),'2');network.stop();await new Promise(r=>setTimeout(r,1100));assert.equal(await readFile(join(dir,'attempts'),'utf8'),'2')}finally{network.close();await rm(dir,{recursive:true,force:true})}});

test('内置私网只清理自己的通用代理和注入凭据，保留NO_PROXY及其他配置',()=>{
 const source:NodeJS.ProcessEnv={HTTP_PROXY:'http://private.invalid',HTTPS_PROXY:'secret',ALL_PROXY:'secret',http_proxy:'secret',https_proxy:'secret',all_proxy:'secret',HtTp_PrOxY:'secret',NO_PROXY:'localhost,100.64.0.0/10',no_proxy:'localhost',PATH:'/safe/path',LANG:'C.UTF-8',HOME:'/safe/home',TS_AUTHKEY:'secret',TS_CLIENT_SECRET:'secret',TS_ID_TOKEN:'secret'};
 const before={...source},parent={...process.env};
 const child=embeddedNetworkEnvironment(source);
 assert.deepEqual(child,{NO_PROXY:source.NO_PROXY,no_proxy:source.no_proxy,PATH:source.PATH,LANG:source.LANG,HOME:source.HOME});
 assert.deepEqual(source,before);assert.ok(Object.keys(process.env).length===Object.keys(parent).length&&Object.keys(parent).every(key=>process.env[key]===parent[key]),"parent environment changed");assert.notEqual(child,source);
});
test('实际内置网络子进程不继承桌面代理，父进程环境保持不变',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'gcollie-net-env-')),binary=join(dir,'stub');
 const keys=['HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy'];
 const previous=Object.fromEntries(keys.map(key=>[key,process.env[key]]));
 const network=new EmbeddedNetwork(dir,4310,binary);
 try{
 for(const key of keys)process.env[key]='http://proxy-fixture.invalid:3128';
 const parent={...process.env};
 await writeFile(binary,`#!/usr/bin/env node
const fs=require('node:fs');fs.writeFileSync(__dirname+'/environment.json',JSON.stringify({proxyKeys:Object.keys(process.env).filter(k=>/^(https?|all)_proxy$/i.test(k)),noProxy:process.env.NO_PROXY,lowerNoProxy:process.env.no_proxy,path:process.env.PATH}));console.log(JSON.stringify({state:'Running',address:'http://100.100.1.2:4310'}));setInterval(()=>{},1000);`,{mode:0o700});
 await network.start();await until(()=>network.status().state==='Running');
 const child=JSON.parse(await readFile(join(dir,'environment.json'),'utf8'));
 assert.deepEqual(child.proxyKeys,[]);assert.equal(child.noProxy,parent.NO_PROXY);assert.equal(child.lowerNoProxy,parent.no_proxy);assert.equal(child.path,parent.PATH);
 assert.ok(Object.keys(process.env).length===Object.keys(parent).length&&Object.keys(parent).every(key=>process.env[key]===parent[key]),"parent environment changed");
 }finally{network.close();for(const key of keys){if(previous[key]===undefined)delete process.env[key];else process.env[key]=previous[key]}await rm(dir,{recursive:true,force:true})}
});
