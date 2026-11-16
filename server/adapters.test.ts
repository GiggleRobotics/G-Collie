import test from 'node:test';import assert from 'node:assert/strict';import{adapterSummaries}from'./adapters.js';
const rows=[{agent:'Codex',nativeId:'c'},{agent:'Hermes',nativeId:'h'},{agent:'Claude Code',nativeId:'owned',readOnly:false},{agent:'Claude Code',nativeId:'terminal',readOnly:true}];
const options={role:'owner',codexEnabled:true,codexLiveIds:['c'],claudeInstalled:true};
test('adapter metadata separates implemented support from confirmed per-session control',()=>{
 const [c,h,a]=adapterSummaries(rows,options);assert.equal(c.capabilities.control,true);assert.equal(a.capabilities.control,true);assert.equal(a.control.confirmedSessions,1);assert.equal(h.capabilities.control,false);assert.equal(h.state,'conditional');assert.match(h.control.condition,/不主动连接/);assert.equal(h.control.supported,true);assert.ok([c,h,a].every(v=>v.capabilities.usage));
});
test('disabled config, missing CLI, archived histories and view role cannot claim control',()=>{
 for(const v of adapterSummaries(rows,{...options,role:'view'})){assert.equal(v.capabilities.control,false);assert.equal(v.control.enabled,false);}
 const [c,,a]=adapterSummaries(rows,{...options,codexEnabled:false,claudeInstalled:false});assert.equal(c.state,'readonly');assert.equal(c.capabilities.control,false);assert.equal(a.capabilities.control,false);
 assert.ok(adapterSummaries(rows.map(s=>({...s,archived:true})),options).every(v=>!v.capabilities.control));
 assert.ok(adapterSummaries([],options).every(v=>!v.capabilities.control));
});
