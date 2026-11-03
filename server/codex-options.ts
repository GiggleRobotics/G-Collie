import {readFileSync,writeFileSync,renameSync} from 'node:fs';import {join} from 'node:path';
export class CodexOptions{
 private values:Record<string,string>={};private path:string;
 constructor(root:string){this.path=join(root,'codex-modes.json');try{this.values=JSON.parse(readFileSync(this.path,'utf8'))}catch{}}
 get(id:string){return this.values[id]||'default'}
 set(id:string,mode:string){if(!['plan','default'].includes(mode)||!/^[a-zA-Z0-9_-]+$/.test(id))throw Error('无效计划模式');this.values[id]=mode;writeFileSync(this.path+'.tmp',JSON.stringify(this.values),{mode:0o600});renameSync(this.path+'.tmp',this.path)}
}
export function collaboration(mode:string|undefined,model:any){if(!mode)return undefined;if(!['plan','default'].includes(mode)||typeof model!=='string'||!model)throw Error('当前模型尚未同步，无法切换计划模式');return{mode,settings:{model,reasoning_effort:null,developer_instructions:null}}}
