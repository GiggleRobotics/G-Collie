import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
export type Schedule={id:string;device:string;session:string;text:string;time:number;interval:number;enabled:boolean;status:string;error?:string;lastRun?:number};
export class Schedules {
 private rows:Schedule[]=[];private busy=false;
 constructor(private path:string,private execute:(task:Schedule)=>Promise<void>){try{this.rows=JSON.parse(readFileSync(path,'utf8'));for(const r of this.rows)if(r.status==='sending'){r.enabled=false;r.status='unknown';r.error='服务重启，发送结果未知，请检查原会话，避免重复发送'}this.save()}catch(e:any){if(e.code!=='ENOENT')throw e}}
 private save(){writeFileSync(this.path+'.tmp',JSON.stringify(this.rows),{mode:0o600});renameSync(this.path+'.tmp',this.path)}
 list(device:string){return this.rows.filter(r=>r.device===device).map(r=>({...r,...(r.error?{error:scheduleError(r.error)}:{})}))}
 upsert(device:string,b:any,id?:string){
  const old=id?this.rows.find(r=>r.id===id&&r.device===device):undefined;if(id&&!old)throw Error('任务不存在');if(old?.status==='sending')throw Error('任务正在发送，暂不能修改');
  if(old&&Object.keys(b).length===1&&typeof b.enabled==='boolean'){if(b.enabled&&old.time<=Date.now())throw Error('请编辑为未来时间后启用');old.enabled=b.enabled;this.save();return old}
  if(typeof b.text!=='string'||!b.text.trim()||b.text.length>4000||!Number.isFinite(b.time)||b.time<=Date.now()||!['new',...((typeof b.session==='string'&&/^codex:[a-zA-Z0-9_-]+$/.test(b.session))?[b.session]:[])].includes(b.session)||![0,18000000,86400000].includes(b.interval))throw Error('请填写消息、未来时间和有效会话');
  const r:Schedule={id:old?.id||randomUUID(),device,session:b.session,text:b.text.trim(),time:b.time,interval:b.interval,enabled:b.enabled!==false,status:'pending'};
  if(old)Object.assign(old,r);else {if(this.rows.filter(r=>r.device===device).length>=100)throw Error('最多保留 100 条定时消息');this.rows.push(r)}this.save();return r;
 }
 remove(device:string,id:string){const r=this.rows.find(r=>r.id===id&&r.device===device);if(!r)throw Error('任务不存在');if(r.status==='sending')throw Error('任务正在发送，暂不能取消');this.rows=this.rows.filter(x=>x!==r);this.save()}
 async tick(now=Date.now()) {if(this.busy)return;this.busy=true;try{for(const r of this.rows){if(!r.enabled||r.time>now)continue;const due=r.time;r.lastRun=now;r.status='sending';delete r.error;if(r.interval){while(r.time<=now)r.time+=r.interval}else r.enabled=false;this.save();try{if(now-due>60000)throw Error('错过发送时间，本次未补发');await this.execute({...r});r.status='sent'}catch(e){r.status='failed';r.error=scheduleError(e)}this.save()}}finally{this.busy=false}}
}

export function scheduleError(error:unknown){const value=error instanceof Error?error.message:String(error);if(/token_revoked|invalidated oauth|401|unauthorized/i.test(value))return 'Codex 登录凭证已失效，请在电脑重新登录后编辑任务时间重试';if(/rate.?limit|quota|额度不足/i.test(value))return 'Codex 额度不足，本次未发送';if(/timeout|超时/i.test(value))return '连接超时，发送结果可能未知，请先检查目标会话';return value.length>180?'发送失败，请查看电脑服务日志或故障诊断':value;}
export async function scheduleLimits(primary:()=>Promise<any>,fallback:()=>Promise<any>){try{return await primary()}catch{try{return await fallback()}catch(e){throw Error(scheduleError(e))}}}
