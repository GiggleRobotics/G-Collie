import{readFileSync,writeFileSync,renameSync}from'node:fs';
import{execFile}from'node:child_process';import{promisify}from'node:util';import{join}from'node:path';
const exec=promisify(execFile);
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
 private local:any;private localAt=0;private localPending?:Promise<any>;private account:any;private accountAt=0;private accountPending?:Promise<any>;
 constructor(private dir:string,private limits:()=>Promise<any>,private accountUsage:()=>Promise<any>){const timer=setInterval(()=>{void this.localRead().catch(()=>{})},60000);timer.unref();void this.localRead().catch(()=>{})}
 private localRead(){if(this.local&&Date.now()-this.localAt<45000)return Promise.resolve(this.local);if(!this.localPending)this.localPending=exec('python3',[join(process.cwd(),'scripts/read-usage.py')],{env:{...process.env,GCOLLIE_DATA_DIR:this.dir},maxBuffer:32*1024*1024,timeout:120000}).then(({stdout})=>{this.local=JSON.parse(stdout);this.localAt=Date.now();return this.local}).finally(()=>{this.localPending=undefined});return this.localPending}
 private accountRead(){if(this.account&&Date.now()-this.accountAt<60000)return Promise.resolve(this.account);if(!this.accountPending)this.accountPending=(async()=>{const results=await Promise.allSettled([this.limits(),this.accountUsage()]);const l=results[0],u=results[1];this.account={fetchedAt:new Date().toISOString(),limits:l.status==='fulfilled'?normalizeLimits(l.value):[],accountKey:l.status==='fulfilled'?l.value.accountKey??null:null,accountLabel:l.status==='fulfilled'?l.value.accountLabel??null:null,resetUnavailableReason:l.status==='fulfilled'?(l.value.accountKey?null:l.value.resetUnavailableReason||'账号标识暂时不可读，请刷新后重试'):'账号额度暂时不可读，请刷新后重试',resetCredits:l.status==='fulfilled'?resetSummary(l.value):null,limitsError:l.status==='rejected'?'账号额度暂时不可读':null,usage:u.status==='fulfilled'?{summary:u.value.summary??null,dailyUsageBuckets:u.value.dailyUsageBuckets??null}:null,usageError:u.status==='rejected'?'当前 Codex 后端未提供账号 Token 统计':null};this.accountAt=Date.now();return this.account})().finally(()=>{this.accountPending=undefined});return this.accountPending}
 invalidateAccount(){this.accountAt=0;this.account=undefined}
 async readAccount(force=false){if(force){await this.accountPending;this.invalidateAccount()}return{codexAccount:await this.accountRead()}}
 async read(force=false){if(force){await this.accountPending;this.invalidateAccount()}const [local,account]=await Promise.all([this.localRead(),this.accountRead()]);return{...local,codexAccount:account}}
}

export function exhaustedCodexWindows(account:any){return (account?.limits||[]).filter((b:any)=>!String(b.id).toLowerCase().includes('review')).flatMap((b:any)=>b.windows||[]).filter((w:any)=>[300,10080].includes(w.windowMinutes)&&typeof w.usedPercent==='number'&&w.usedPercent>=100)}
