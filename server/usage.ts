import{execFile}from'node:child_process';import{promisify}from'node:util';import{join}from'node:path';
const exec=promisify(execFile);
export function normalizeLimits(raw:any){
 const source=raw?.rateLimitsByLimitId&&Object.keys(raw.rateLimitsByLimitId).length?Object.values(raw.rateLimitsByLimitId):raw?.rateLimits?[raw.rateLimits]:[];
 return source.map((bucket:any)=>({id:bucket.limitId||'codex',name:bucket.limitName||bucket.limitId||'Codex',plan:bucket.planType||null,windows:['primary','secondary'].flatMap(k=>{const w=bucket[k];return w&&typeof w.usedPercent==='number'?[{usedPercent:w.usedPercent,windowMinutes:w.windowDurationMins??null,resetsAt:w.resetsAt??null}]:[]})}));
}
export class UsageService{
 private local:any;private localAt=0;private localPending?:Promise<any>;private account:any;private accountAt=0;private accountPending?:Promise<any>;
 constructor(private dir:string,private limits:()=>Promise<any>,private accountUsage:()=>Promise<any>){const timer=setInterval(()=>{void this.localRead().catch(()=>{})},60000);timer.unref();void this.localRead().catch(()=>{})}
 private localRead(){if(this.local&&Date.now()-this.localAt<45000)return Promise.resolve(this.local);if(!this.localPending)this.localPending=exec('python3',[join(process.cwd(),'scripts/read-usage.py')],{env:{...process.env,GCOLLIE_DATA_DIR:this.dir},maxBuffer:32*1024*1024,timeout:120000}).then(({stdout})=>{this.local=JSON.parse(stdout);this.localAt=Date.now();return this.local}).finally(()=>{this.localPending=undefined});return this.localPending}
 private accountRead(){if(this.account&&Date.now()-this.accountAt<60000)return Promise.resolve(this.account);if(!this.accountPending)this.accountPending=(async()=>{const results=await Promise.allSettled([this.limits(),this.accountUsage()]);const l=results[0],u=results[1];this.account={fetchedAt:new Date().toISOString(),limits:l.status==='fulfilled'?normalizeLimits(l.value):[],limitsError:l.status==='rejected'?'账号额度暂时不可读':null,usage:u.status==='fulfilled'?{summary:u.value.summary??null,dailyUsageBuckets:u.value.dailyUsageBuckets??null}:null,usageError:u.status==='rejected'?'当前 Codex 后端未提供账号 Token 统计':null};this.accountAt=Date.now();return this.account})().finally(()=>{this.accountPending=undefined});return this.accountPending}
 async read(){const [local,account]=await Promise.all([this.localRead(),this.accountRead()]);return{...local,codexAccount:account}}
}
