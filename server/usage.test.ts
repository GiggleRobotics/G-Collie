import {mkdtempSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {UsageService} from './usage.js';
import test from'node:test';import assert from'node:assert/strict';import{execFileSync}from'node:child_process';import{normalizeLimits}from'./usage';
test('usage index: cumulative mirrors, cache semantics, missing history and persisted sampling',()=>{execFileSync('python3',['scripts/test-usage.py'],{stdio:'pipe'})});
test('limits preserve bucket windows and do not invent absent 5-hour allowance',()=>{const r=normalizeLimits({rateLimits:{primary:{usedPercent:1}},rateLimitsByLimitId:{codex:{limitId:'codex',secondary:{usedPercent:71,windowDurationMins:10080,resetsAt:123}}}});assert.equal(r.length,1);assert.deepEqual(r[0].windows,[{usedPercent:71,windowMinutes:10080,resetsAt:123}]);assert.deepEqual(normalizeLimits({}),[])});

test('Codex child proxy configuration only accepts network environment keys',async()=>{const{mkdtempSync,writeFileSync,rmSync}=await import('node:fs');const{tmpdir}=await import('node:os');const{join}=await import('node:path');const{codexEnvironment}=await import('./codex');const dir=mkdtempSync(join(tmpdir(),'gcollie-proxy-test-'));try{writeFileSync(join(dir,'codex-network-env.json'),JSON.stringify({NO_PROXY:'example.test',NODE_OPTIONS:'--bad-option',GCOLLIE_FAKE_KEY:'bad'}));const env=codexEnvironment(dir);assert.equal(env.NODE_OPTIONS,process.env.NODE_OPTIONS);assert.equal(env.GCOLLIE_FAKE_KEY,undefined);assert.equal(env.NO_PROXY,process.env.NO_PROXY||'example.test')}finally{rmSync(dir,{recursive:true,force:true})}});

test('exhausted windows require actual Codex limits and preserve missing data',async()=>{
 const {exhaustedCodexWindows}=await import('./usage.js');
 assert.deepEqual(exhaustedCodexWindows({}),[]);
 assert.deepEqual(exhaustedCodexWindows({limits:[{id:'code-review',windows:[{windowMinutes:300,usedPercent:100}]}]}),[]);
 assert.deepEqual(exhaustedCodexWindows({limits:[{id:'codex',windows:[{windowMinutes:300,usedPercent:99},{windowMinutes:10080,usedPercent:100}]}]}),[{windowMinutes:10080,usedPercent:100}]);
});

test('account limits do not wait for unavailable token statistics and classify expired login',async()=>{
 const {UsageService}=await import('./usage.js');
 const dir=(await import('node:fs')).mkdtempSync('/tmp/gcollie-usage-isolation-');
 const service=new UsageService(dir,async()=>({accountKey:'test',rateLimits:{primary:{usedPercent:100,windowDurationMins:300}}}),()=>new Promise(()=>{}));
 const result=await Promise.race([service.readAccount(),new Promise<never>((_,reject)=>{const t=setTimeout(()=>reject(Error('limits blocked by token usage')),1000);t.unref()})]);
 assert.equal(result.codexAccount.limits[0].windows[0].usedPercent,100);
 assert.equal(result.codexAccount.usageLoading,true);
 const failed=new UsageService(dir,async()=>{throw Error('401 token_revoked')},async()=>({}));
 const snapshot=await failed.readAccount();assert.equal(snapshot.codexAccount.limitsErrorCode,'auth_expired');assert.deepEqual(snapshot.codexAccount.limits,[]);
});

test('manual account refresh honors failure cooldown and records merge metrics',async()=>{const{UsageService}=await import('./usage.js');const{mkdtempSync}=await import('node:fs');let calls=0;const service=new UsageService(mkdtempSync('/tmp/gcollie-backoff-'),async()=>{calls++;throw Error('429')},async()=>({}));await Promise.all([service.readAccount(true),service.readAccount(true)]);await service.readAccount(true);assert.equal(calls,1);assert.equal(service.metrics().failures,1);assert.ok(service.metrics().nextRetryAt!>Date.now());});

import {readQuotaWithFallback} from './usage.js';
test('quota read recovers from revoked CLI credentials using a valid desktop window',async()=>{
 const raw={rateLimits:{primary:{usedPercent:35,windowDurationMins:300}}};
 assert.deepEqual((await readQuotaWithFallback(async()=>{throw Error('401 token_revoked')},async()=>raw)).rateLimits,raw.rateLimits);
 await assert.rejects(readQuotaWithFallback(async()=>{throw Error('401 token_revoked')},async()=>({})),/token_revoked/);
 let reads=0;await assert.rejects(readQuotaWithFallback(async()=>{throw Error('429')},async()=>{reads++;return raw}),/429/);assert.equal(reads,0);
});
test('account replacement bypasses old cooldown and discards late old-account responses',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'gcollie-switch-'));let identity='A',calls=0,finish!:(v:any)=>void;
 const service=new UsageService(dir,async()=>{calls++;if(identity==='A')return new Promise(r=>finish=r);return{accountKey:'B',rateLimits:{primary:{usedPercent:12,windowDurationMins:300}}}},async()=>({}),()=>identity);
 const old=service.readAccount();await new Promise(r=>setImmediate(r));identity='B';
 const current=await service.readAccount();assert.equal(current.codexAccount.accountKey,'B');
 finish({accountKey:'A',rateLimits:{primary:{usedPercent:100,windowDurationMins:300}}});
 assert.equal((await old).codexAccount.accountKey,'B');assert.equal((await service.readAccount()).codexAccount.accountKey,'B');assert.equal(calls,2);
});
test('new login automatically invalidates auth-failure cooldown',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'gcollie-relogin-'));let revision='old';
 const service=new UsageService(dir,async()=>{if(revision==='old')throw Error('401 token_revoked');return{accountKey:'new',rateLimits:{primary:{usedPercent:1,windowDurationMins:300}}}},async()=>({}),()=>revision);
 assert.equal((await service.readAccount()).codexAccount.limitsErrorCode,'auth_expired');revision='new';assert.equal((await service.readAccount()).codexAccount.accountKey,'new');
});
test('background polling follows login replacement without a client refresh',async(t)=>{
 t.mock.timers.enable({apis:['setInterval']});
 const dir=mkdtempSync(join(tmpdir(),'gcollie-background-login-'));let identity='A',calls=0;
 const service=new UsageService(dir,async()=>{calls++;return{accountKey:identity,rateLimits:{primary:{usedPercent:1,windowDurationMins:300}}}},async()=>({}),()=>identity);
 await service.readAccount();identity='B';t.mock.timers.tick(5000);
 await new Promise(r=>setImmediate(r));
 assert.equal(calls,2);assert.equal((await service.readAccount()).codexAccount.accountKey,'B');
});
