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
