import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';

type CreateReceipt =
 | {state:'missing'|'sending'|'unknown'}
 | {state:'failed';error:string;code?:string;attachmentId?:string}
 | {state:'done';result:any};

export class SessionCreateError extends Error {
 constructor(message:string,readonly outcome:'failed'|'sending'|'unknown',readonly code='session_create_'+outcome,readonly attachmentId?:string){
  super(message);
 }
}

export function createNotSubmitted(error:unknown,code?:string){
 return new SessionCreateError(error instanceof Error?error.message:String(error),'failed',code);
}

// One ledger covers create + first prompt, so retries cannot start a second turn.
export class SessionCreation {
 private ledger:Record<string,Exclude<CreateReceipt,{state:'missing'}>>={};
 private active=new Set<string>();
 constructor(private dir:string){try{this.ledger=JSON.parse(readFileSync(join(dir,'session-create-ledger.json'),'utf8'))}catch{}}
 private save(){const p=join(this.dir,'session-create-ledger.json');writeFileSync(p+'.tmp',JSON.stringify(this.ledger),{mode:0o600});renameSync(p+'.tmp',p)}
 private key(device:string,id:string){
  if(typeof id!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(id))throw createNotSubmitted(Error('无效操作编号'));
  return device+':'+id;
 }
 receipt(device:string,id:string):CreateReceipt{
  const key=this.key(device,id);
  const row=this.ledger[key];
  if(!row)return{state:'missing'};
  if(row.state==='sending'&&!this.active.has(key))return{state:'unknown'};
  return row;
 }
 async run(device:string,id:string,create:()=>Promise<any>){
  const key=this.key(device,id);
  const old=this.receipt(device,id);
  if(old.state==='done')return old.result;
  if(old.state==='sending')throw new SessionCreateError('新建正在提交，请等待回执','sending');
  if(old.state==='unknown')throw new SessionCreateError('新建已提交或结果未知，请刷新列表确认，勿重复发送','unknown');
  this.active.add(key);
  this.ledger[key]={state:'sending'};
  try{
   this.save();
   const result=await create();
   this.ledger[key]={state:'done',result};
   this.save();
   return result;
  }catch(e){
   const failed=e instanceof SessionCreateError&&e.outcome==='failed';
   this.ledger[key]=failed?{state:'failed',error:e.message,...(e.attachmentId?{code:e.code,attachmentId:e.attachmentId}:{})}:{state:'unknown'};
   this.save();
   if(failed)throw e;
   throw new SessionCreateError(e instanceof Error?e.message:String(e),'unknown');
  }finally{
   this.active.delete(key);
  }
 }
}

export function sessionTitle(prompt:string){return [...prompt.trim().replace(/\s+/g,' ')].slice(0,40).join('')||'新会话'}
