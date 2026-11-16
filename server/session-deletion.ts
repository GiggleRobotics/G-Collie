import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';
export type DeleteEligibility={supported:boolean;allowed:boolean;reason:string;code:string;source:string};
export class DeleteFailure extends Error{constructor(message:string,public code:string,public outcome:'failed'|'unknown'='failed'){super(message)}}
export type DeleteProvider={inspect:(id:string)=>Promise<DeleteEligibility&{revision?:number;generation?:number}>;remove:(id:string,requestId:string,state:{revision?:number;generation?:number})=>Promise<void|{deletedIds?:string[]}>};
export class SessionDeletion{
 private records:Record<string,any>={};private busy=new Set<string>();private requests=new Set<string>();
 constructor(private root:string,private provider:DeleteProvider){try{this.records=JSON.parse(readFileSync(join(root,'session-deletions.json'),'utf8'));if(!this.records||typeof this.records!=='object'||Array.isArray(this.records)||Object.entries(this.records).some(([key,row])=>!/^[a-zA-Z0-9_-]{8,100}$/.test(key)||!row||typeof row.id!=='string'||!/^hermes:[a-zA-Z0-9_-]+$/.test(row.id)||!['sending','unknown','failed','done'].includes(row.state)))throw Error()}catch(e:any){if(e.code!=='ENOENT')throw Error('删除操作记录无法读取，拒绝启动')}}
 private save(){const path=join(this.root,'session-deletions.json');writeFileSync(path+'.tmp',JSON.stringify(this.records),{mode:0o600});renameSync(path+'.tmp',path)}
 async eligibility(id:string,role:string):Promise<DeleteEligibility>{
  if(!/^(hermes|codex|claude):[a-zA-Z0-9_-]+$/.test(id))return{supported:false,allowed:false,reason:'此会话来源不支持删除',code:'delete_unsupported',source:id.split(':')[0]};
  const source=id.split(':')[0];if(source!=='hermes')return{supported:false,allowed:false,reason:source==='codex'?'当前连接尚未验证 Codex 原生删除安全条件，请在电脑操作':'当前连接尚未适配 Claude Code 安全的单会话删除，请在电脑操作',code:'delete_unsupported',source};
  if(role==='view')return{supported:true,allowed:false,reason:'当前设备为只读权限',code:'delete_readonly',source};
  if(this.busy.has(id))return{supported:true,allowed:false,reason:'此会话有删除正在提交',code:'delete_pending',source};
  if(Object.values(this.records).some(r=>r.id===id&&['sending','unknown'].includes(r.state)))return{supported:true,allowed:false,reason:'上次删除结果未知，请先在电脑核对；不会自动重复删除',code:'delete_result_unknown',source};
  try{const {revision,generation,...state}=await this.provider.inspect(id.slice(7));return state}catch{return{supported:true,allowed:false,reason:'电脑后端离线或状态无法确认，暂不能删除',code:'delete_unavailable',source}};
 }
 async remove(id:string,requestId:string,role:string){
  if(typeof requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(requestId))throw new DeleteFailure('无效删除操作编号','delete_invalid_request');
  if(role==='view')throw new DeleteFailure('当前设备为只读权限','delete_readonly');
  const old=this.records[requestId];if(old){if(old.id!==id)throw new DeleteFailure('操作编号已用于其他会话','delete_request_conflict');if(old.state==='done')return{ok:true,id,deleted:true,...(old.deletedIds?{deletedIds:old.deletedIds}:{})};if(old.state==='failed')throw new DeleteFailure(old.error,old.code);throw new DeleteFailure('删除结果未知，请先在电脑核对；不会重复提交','delete_result_unknown','unknown')}
  if(this.requests.has(requestId))throw new DeleteFailure('删除操作编号正在使用，请等待原操作结果','delete_request_conflict');this.requests.add(requestId);
  try{
  const state=await this.eligibility(id,role);if(!state.allowed)throw new DeleteFailure(state.reason,state.code);
  if(this.busy.has(id))throw new DeleteFailure('删除正在提交','delete_pending');this.busy.add(id);
  try{
   let fresh:Awaited<ReturnType<DeleteProvider['inspect']>>;try{fresh=await this.provider.inspect(id.slice(7))}catch{throw new DeleteFailure('电脑后端状态无法确认，未提交删除，请刷新后重试','delete_unavailable')}if(!fresh.allowed)throw new DeleteFailure(fresh.reason,fresh.code);
   this.records[requestId]={id,state:'sending'};this.save();
   let removed:void|{deletedIds?:string[]};try{removed=await this.provider.remove(id.slice(7),requestId,fresh)}catch(e){const known=e instanceof DeleteFailure&&e.outcome==='failed';this.records[requestId]={id,state:known?'failed':'unknown',error:known?e.message:'删除结果未知，请先在电脑核对',code:known?e.code:'delete_result_unknown'};this.save();if(known)throw e;throw new DeleteFailure('删除结果未知，请先在电脑核对；不会自动重试','delete_result_unknown','unknown')}
   const deletedIds=removed?.deletedIds;this.records[requestId]={id,state:'done',...(deletedIds?{deletedIds}:{})};this.save();return{ok:true,id,deleted:true,...(deletedIds?{deletedIds}:{})};
  }finally{this.busy.delete(id)}
  }finally{this.requests.delete(requestId)}
 }
}
