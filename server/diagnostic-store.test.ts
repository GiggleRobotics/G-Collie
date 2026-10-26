import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DiagnosticStore,diagnosticRows} from './diagnostic-store.js';
test('diagnostic requests survive restart, bind device and range, and deduplicate replies',()=>{
 const dir=mkdtempSync(join(tmpdir(),'collie-diag-'));
 try{
  let store=new DiagnosticStore(dir);const to=Date.now(),from=to-60000;
  const request=store.request('phone-a',from,to);store=new DiagnosticStore(dir);
  assert.equal(store.pending('phone-a')[0].id,request.id);assert.equal(store.pending('phone-b').length,0);
  const body={requestId:request.id,from:new Date(from).toISOString(),to:new Date(to).toISOString(),events:[{time:new Date(to-1).toISOString(),route:'/connection',category:'offline',password:'SECRET',text:'PRIVATE'}]};
  assert.throws(()=>store.upload('phone-b',body));assert.throws(()=>store.upload('phone-a',{...body,from:new Date(from+1).toISOString()}));
  const first=store.upload('phone-a',body);assert.deepEqual(store.upload('phone-a',body),first);assert.equal(store.pending('phone-a').length,0);assert.equal(store.packs('phone-a',from,to).length,1);
  assert.ok(!JSON.stringify(store.packs('phone-a',from,to)).includes('SECRET'));assert.ok(!JSON.stringify(store.packs('phone-a',from,to)).includes('PRIVATE'));
 }finally{rmSync(dir,{recursive:true,force:true})}
});
test('diagnostics sample fast successful requests while preserving failures',()=>{
 const dir=mkdtempSync(join(tmpdir(),'collie-diag-'));
 try{const store=new DiagnosticStore(dir);for(let i=0;i<3;i++)store.record({method:'GET',route:'/health',status:200,durationMs:1});for(let i=0;i<2;i++)store.record({method:'GET',route:'/health',status:429,durationMs:1});assert.equal(store.events(Date.now()-60000,Date.now()+1000).length,3);assert.throws(()=>diagnosticRows([{time:'invalid'}]));}finally{rmSync(dir,{recursive:true,force:true})}
});
