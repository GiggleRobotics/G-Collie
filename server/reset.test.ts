import test from 'node:test';
import assert from 'node:assert/strict';
import {ResetService,resetSummary,UsageService} from './usage';
const body={accountKey:'account-a',idempotencyKey:'reset-attempt-123456'};
test('reset summary preserves unknown, count-only and authoritative total',()=>{
 assert.equal(resetSummary({}),null);
 assert.deepEqual(resetSummary({rateLimitResetCredits:{availableCount:2,credits:null}}),{availableCount:2,credits:null});
 assert.equal(resetSummary({rateLimitResetCredits:{availableCount:4,credits:[]}})?.availableCount,4);
 assert.equal(resetSummary({rateLimitResetCredits:{availableCount:-1}}),null);
});
test('reset validates input and account identity before consuming',async()=>{
 let calls=0;const service=new ResetService(async()=>({accountKey:'account-b'}),async()=>{calls++;return{outcome:'reset'}},()=>{});
 await assert.rejects(service.reset({}),/无效/);
 await assert.rejects(service.reset(body),/账号已变化/);
 assert.equal(calls,0);
});
test('concurrent identical attempts share consumption and other attempts are blocked',async()=>{
 let release!:()=>void;const gate=new Promise<void>(r=>release=r);let calls=0,invalidations=0;
 const service=new ResetService(async()=>({accountKey:'account-a'}),async(params)=>{assert.equal(params.idempotencyKey,body.idempotencyKey);calls++;await gate;return {outcome:'reset'}},()=>invalidations++);
 const first=service.reset(body),second=service.reset(body);
 await assert.rejects(service.reset({...body,idempotencyKey:'other-attempt-123456'}),/正在处理/);
 release();assert.deepEqual(await first,{outcome:'reset'});assert.deepEqual(await second,{outcome:'reset'});
 assert.equal(calls,1);assert.equal(invalidations,1);
});
test('uncertain failures retain upstream idempotency key and invalidate cached limits',async()=>{
 const keys:string[]=[];let invalidations=0;
 const service=new ResetService(async()=>({accountKey:'account-a'}),async p=>{keys.push(p.idempotencyKey);if(keys.length===1)throw Error('timeout');return{outcome:'alreadyRedeemed'}},()=>invalidations++);
 await assert.rejects(service.reset(body),/timeout/);
 assert.deepEqual(await service.reset(body),{outcome:'alreadyRedeemed'});
 assert.deepEqual(keys,[body.idempotencyKey,body.idempotencyKey]);assert.equal(invalidations,2);
});
test('all documented outcomes pass through; unknown outcomes remain uncertain',async()=>{
 for(const outcome of ['reset','alreadyRedeemed','nothingToReset','noCredit','unknown']){
  const service=new ResetService(async()=>({accountKey:'account-a'}),async()=>({outcome}),()=>{});
  if(outcome==='unknown')await assert.rejects(service.reset(body),/未知/);else assert.equal((await service.reset(body)).outcome,outcome);
 }
});
test('forced account refresh waits for stale in-flight request and reads again',async()=>{
 let release!:()=>void;const gate=new Promise<void>(r=>release=r);let calls=0;
 const service=new UsageService('/tmp',async()=>{const n=++calls;if(n===1)await gate;return{accountKey:'a',rateLimitResetCredits:{availableCount:n,credits:null}}},async()=>({}));
 // Avoid invoking the unrelated Python local index for this account cache test.
 const account=(service as any).accountRead();
 (service as any).localRead=async()=>({});
 const refreshed=service.read(true);release();await account;
 assert.equal((await refreshed).codexAccount.resetCredits.availableCount,2);
});
test('selected card is forwarded and an uncertain attempt cannot switch cards',async()=>{
 const calls:any[]=[];const service=new ResetService(async()=>({accountKey:'account-a'}),async p=>{calls.push(p);throw Error('simulated timeout')},()=>{});
 await assert.rejects(service.reset({...body,creditId:'card-two'}),/timeout/);
 await assert.rejects(service.reset({...body,creditId:'card-one'}),/不能更换/);
 await assert.rejects(service.reset({...body,creditId:'card-two'}),/timeout/);
 assert.equal(calls.length,2);assert.equal(calls[0].creditId,'card-two');assert.deepEqual(calls[0],calls[1]);
});

test('concurrent force refreshes merge and repeated clicks respect minimum interval',async()=>{
 let calls=0;
 const service=new UsageService('/tmp',async()=>{calls++;return{accountKey:'a'}},async()=>({}));
 (service as any).localRead=async()=>({});
 await Promise.all(Array.from({length:20},()=>service.readAccount(true)));
 assert.equal(calls,1);
 await service.readAccount(true);assert.equal(calls,1);
 service.invalidateAccount();await service.readAccount(true);assert.equal(calls,2);
});
