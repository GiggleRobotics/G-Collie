import {homedir} from 'node:os';
import{readFileSync,writeFileSync,renameSync,statSync}from'node:fs';
import{execFile}from'node:child_process';import{promisify}from'node:util';import{join}from'node:path';
const exec=promisify(execFile);
// Only file metadata is observed; credentials are never read or logged here.
export function accountRevision(root:string){return[join(process.env.CODEX_HOME||join(homedir(),'.codex'),'auth.json'),join(root,'desktop-runtime.json')].map(path=>{try{const s=statSync(path);return`${s.ino}:${s.size}:${s.mtimeMs}`}catch{return'missing'}}).join('|')}
// A revoked CLI token does not invalidate desktop chat authentication.
export async function readQuotaWithFallback(primary:()=>Promise<any>,desktop:()=>Promise<any>){
 try{return await primary()}catch(primaryError){
  if(/429|rate.limit/i.test(String(primaryError)))throw primaryError;
  try{const value=await desktop();if(!normalizeLimits(value).some(b=>b.windows.length))throw Error('桌面额度未返回可用窗口');return{...value,resetUnavailableReason:value.accountKey?null:'账号标识暂时不可读，请刷新后重试'}}catch{throw primaryError}
 }
}
export function normalizeLimits(raw:any){
 const source=raw?.rateLimitsByLimitId&&Object.keys(raw.rateLimitsByLimitId).length?Object.values(raw.rateLimitsByLimitId):raw?.rateLimits?[raw.rateLimits]:[];
 return source.map((bucket:any)=>({id:bucket.limitId||'codex',name:bucket.limitName||bucket.limitId||'Codex',plan:bucket.planType||null,windows:['primary','secondary'].flatMap(k=>{const w=bucket[k];return w&&typeof w.usedPercent==='number'?[{usedPercent:w.usedPercent,windowMinutes:w.windowDurationMins??null,resetsAt:w.resetsAt??null}]:[]})}));
}
export function resetSummary(raw:any){const value=raw?.rateLimitResetCredits;if(!value||!Number.isInteger(value.availableCount)||value.availableCount<0)return null;return {availableCount:value.availableCount,credits:Array.isArray(value.credits)?value.credits.map((c:any)=>({id:c.id,resetType:c.resetType,grantedAt:c.grantedAt,status:c.status,title:c.title,description:c.description,expiresAt:c.expiresAt})):null}}
export class ResetService{
 private pending?:{key:string;promise:Promise<any>};
 private attempts:Record<string,string>={};
 constructor(private limits:()=>Promise<any>,private consume:(p:{idempotencyKey:string;creditId?:string})=>Promise<any>,private invalidate:()=>void,private ledgerPath?:string){if(ledgerPath){try{this.attempts=JSON.parse(readFileSync(ledgerPath,'utf8'))}catch(e:any){if(e.code!=='ENOENT')throw e}}}
 async reset(body:any){
  if(typeof body?.idempotencyKey!=='string'||! /^[a-zA-Z0-9_-]{16,100}$/.test(body.idempotencyKey)||typeof body.accountKey!=='string'||!body.accountKey||body.accountKey.length>500)throw Error('无效重置请求，请刷新账号额度');
  if(body.creditId!==undefined&&(typeof body.creditId!=='string'||!body.creditId.trim()||body.creditId.length>500))throw Error('无效重置卡');
  const key=JSON.stringify([body.accountKey,body.idempotencyKey,body.creditId??null]);
  const attempt=JSON.stringify([body.accountKey,body.idempotencyKey]);const card=JSON.stringify(body.creditId??null);if(this.attempts[attempt]!==undefined&&this.attempts[attempt]!==card)throw Error('原重置操作不能更换卡片');if(this.attempts[attempt]===undefined){this.attempts[attempt]=card;if(this.ledgerPath){writeFileSync(this.ledgerPath+'.tmp',JSON.stringify(this.attempts),{mode:0o600});renameSync(this.ledgerPath+'.tmp',this.ledgerPath)}}
  if(this.pending){if(this.pending.key===key)return this.pending.promise;throw Error('正在处理另一次重置，请稍候刷新')}
  const promise=(async()=>{const snapshot=await this.limits();if(snapshot.accountKey!==body.accountKey)throw Error('Codex 账号已变化，请刷新后重新确认');try{const result=await this.consume({idempotencyKey:body.idempotencyKey,...(body.creditId?{creditId:body.creditId}:{})});if(!['reset','alreadyRedeemed','nothingToReset','noCredit'].includes(result?.outcome))throw Error('重置结果未知，请使用原操作重试');return result}finally{this.invalidate()}})();
  this.pending={key,promise};try{return await promise}finally{this.pending=undefined}
 }
}
export class UsageService{
 private local:any;private localAt=0;private localPending?:Promise<any>;private account:any;private accountAt=0;private accountPending?:Promise<any>;private refreshPending?:Promise<any>;
 constructor(private dir:string,private limits:()=>Promise<any>,private accountUsage:()=>Promise<any>,private revision:()=>string=()=>'' ){const identityTimer=setInterval(()=>{this.syncIdentity();void this.accountRead().catch(()=>{})},5000);identityTimer.unref();const timer=setInterval(()=>{void this.localRead().catch(()=>{})},60000);timer.unref();void this.localRead().catch(()=>{})}
 private localRead(){if(this.local&&Date.now()-this.localAt<45000)return Promise.resolve(this.local);if(!this.localPending)this.localPending=exec('python3',[join(process.cwd(),'scripts/read-usage.py')],{env:{...process.env,GCOLLIE_DATA_DIR:this.dir},maxBuffer:32*1024*1024,timeout:120000}).then(({stdout})=>{this.local=JSON.parse(stdout);this.localAt=Date.now();return this.local}).finally(()=>{this.localPending=undefined});return this.localPending}
 private accountFailures=0;private nextAccountAttempt=0;private counters={limitsCalls:0,cacheHits:0,coalesced:0,failures:0};
 metrics(){return{...this.counters,nextRetryAt:this.nextAccountAttempt||null}}
 private observedRevision:string|undefined;private epoch=0;
 private syncIdentity(){const next=this.revision();if(next!==this.observedRevision){this.observedRevision=next;this.epoch++;this.invalidateAccount();this.usageData=null;this.usageError=null;this.usageAt=0;this.usagePending=undefined;this.accountPending=undefined;this.refreshPending=undefined;this.accountFailures=0}}
 private usageData:any=null;private usageError:string|null=null;private usagePending?:Promise<void>;private usageAt=0;
 private refreshUsage(){if(Date.now()-this.usageAt<60000||this.usagePending)return;const epoch=this.epoch,accountKey=this.account?.accountKey;this.usagePending=this.accountUsage().then(u=>{if(epoch!==this.epoch||accountKey!==this.account?.accountKey)return;this.usageData={summary:u.summary??null,dailyUsageBuckets:u.dailyUsageBuckets??null};this.usageError=null}).catch(()=>{if(epoch!==this.epoch||accountKey!==this.account?.accountKey)return;this.usageError='账号 Token 统计暂时不可读'}).finally(()=>{if(epoch!==this.epoch)return;this.usageAt=accountKey===this.account?.accountKey?Date.now():0;this.usagePending=undefined});}
 private accountRead():Promise<any>{this.syncIdentity();this.refreshUsage();if(this.account&&(Date.now()-this.accountAt<60000||Date.now()<this.nextAccountAttempt)){this.counters.cacheHits++;return Promise.resolve(this.account);}if(this.accountPending)this.counters.coalesced++;const epoch=this.epoch;if(!this.accountPending)this.accountPending=(async()=>{this.counters.limitsCalls++;const results=await Promise.allSettled([this.limits()]);const l=results[0];if(epoch!==this.epoch)return this.accountRead();if(l.status==='rejected'){this.counters.failures++;this.accountFailures=Math.min(6,this.accountFailures+1);this.nextAccountAttempt=Date.now()+Math.min(120000,5000*2**this.accountFailures)+Math.floor(Math.random()*1000);}else{this.accountFailures=0;this.nextAccountAttempt=0;}if(l.status==='fulfilled'&&this.account?.accountKey!==l.value.accountKey){this.usageData=null;this.usageError=null;this.usageAt=0;}this.account={fetchedAt:new Date().toISOString(),limits:l.status==='fulfilled'?normalizeLimits(l.value):[],accountKey:l.status==='fulfilled'?l.value.accountKey??null:null,accountLabel:l.status==='fulfilled'?l.value.accountLabel??null:null,resetUnavailableReason:l.status==='fulfilled'?(l.value.accountKey?null:l.value.resetUnavailableReason||'账号标识暂时不可读，请刷新后重试'):'账号额度暂时不可读，请刷新后重试',resetCredits:l.status==='fulfilled'?resetSummary(l.value):null,limitsError:l.status==='rejected'?'账号额度暂时不可读':null,limitsErrorCode:l.status==='rejected'?(/401|token_revoked|invalidated oauth/i.test(String(l.reason))?'auth_expired':/429|rate.limit/i.test(String(l.reason))?'rate_limited':'upstream_unavailable'):null,usage:this.usageData,usageError:this.usageError,usageLoading:!!this.usagePending};this.accountAt=l.status==='fulfilled'?Date.now():Date.now()-50000;return this.account})().finally(()=>{if(epoch===this.epoch)this.accountPending=undefined});return this.accountPending}
 invalidateAccount(){this.accountAt=0;this.account=undefined;this.nextAccountAttempt=0}
 private refreshAccount(){this.syncIdentity();if(this.account&&Date.now()<this.nextAccountAttempt)return Promise.resolve(this.account);if(!this.refreshPending)this.refreshPending=(async()=>{const previous=this.accountPending;if(previous)await previous;else if(this.account&&Date.now()-this.accountAt<10000)return this.account;this.invalidateAccount();return await this.accountRead()})().finally(()=>{this.refreshPending=undefined});return this.refreshPending}
 async readAccount(force=false){const a=await(force?this.refreshAccount():this.accountRead());return{codexAccount:{...a,usage:this.usageData,usageError:this.usageError,usageLoading:!!this.usagePending}}}
 async read(force=false){const [local,account]=await Promise.all([this.localRead(),force?this.refreshAccount():this.accountRead()]);return{...local,codexAccount:{...account,usage:this.usageData,usageError:this.usageError,usageLoading:!!this.usagePending}}}

}

export function exhaustedCodexWindows(account:any){return (account?.limits||[]).filter((b:any)=>!String(b.id).toLowerCase().includes('review')).flatMap((b:any)=>b.windows||[]).filter((w:any)=>[300,10080].includes(w.windowMinutes)&&typeof w.usedPercent==='number'&&w.usedPercent>=100)}
