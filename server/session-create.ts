import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';

// One ledger covers create + first prompt, so retries cannot start a second turn.
export class SessionCreation {
 private ledger:Record<string,{state:string;result?:any}>={};
 constructor(private dir:string){try{this.ledger=JSON.parse(readFileSync(join(dir,'session-create-ledger.json'),'utf8'))}catch{}}
 private save(){const p=join(this.dir,'session-create-ledger.json');writeFileSync(p+'.tmp',JSON.stringify(this.ledger),{mode:0o600});renameSync(p+'.tmp',p)}
 async run(device:string,id:string,create:()=>Promise<any>){
  if(typeof id!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(id))throw Error('无效操作编号');
  const key=device+':'+id,old=this.ledger[key];
  if(old){if(old.state==='done')return old.result;throw Error('新建已提交或结果未知，请刷新列表确认，勿重复发送')}
  this.ledger[key]={state:'sending'};this.save();
  try{const result=await create();this.ledger[key]={state:'done',result};this.save();return result}
  catch(e){this.ledger[key]={state:'unknown'};this.save();throw e}
 }
}
export function sessionTitle(prompt:string){return [...prompt.trim().replace(/\s+/g,' ')].slice(0,40).join('')||'新会话'}
