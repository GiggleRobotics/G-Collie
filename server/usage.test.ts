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
