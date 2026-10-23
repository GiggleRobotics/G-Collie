import {readdir,realpath,stat,mkdir,access,readFile,writeFile,rename} from 'node:fs/promises';
import {join,relative,basename,isAbsolute,sep} from 'node:path';
import {homedir} from 'node:os';
import {constants,existsSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {codexEnvironment} from './codex.js';

export class FolderProjects {
 constructor(private dir:string,private home=homedir()){}
 async folder(path:string){
  if(typeof path!=='string'||!isAbsolute(path)||path.includes('\0'))throw Error('请选择有效文件夹');
  const root=await realpath(this.home),resolved=await realpath(path),rel=relative(root,resolved);
  if(rel==='..'||rel.startsWith('..'+sep)||isAbsolute(rel)||rel.split(sep).some(p=>p.startsWith('.')))throw Error('请选择用户目录中的普通文件夹');
  if(!(await stat(resolved)).isDirectory())throw Error('所选路径不是文件夹');
  await access(resolved,constants.R_OK|constants.X_OK);return resolved;
 }
 async browse(path?:string){const root=await realpath(this.home),current=await this.folder(path||root);
  const entries=await readdir(current,{withFileTypes:true});
  return{path:current,parent:current===root?null:join(current,'..'),folders:entries.filter(e=>e.isDirectory()&&!e.name.startsWith('.')).sort((a,b)=>a.name.localeCompare(b.name)).slice(0,500).map(e=>({name:e.name,path:join(current,e.name)}))};
 }
 async createFolder(parent:string,name:string){
  const path=await this.folder(parent);
  if(typeof name!=='string'||!name.trim()||name!==name.trim()||name.length>100||name.startsWith('.')||/[\\/\x00-\x1f]/.test(name))throw Error('请输入有效文件夹名称，不要包含斜杠或隐藏目录前缀');
  const target=join(path,name);await mkdir(target);return{path:await this.folder(target),name};
 }
 async list(){try{return JSON.parse(await readFile(join(this.dir,'folder-projects.json'),'utf8')) as {path:string;name:string;agents:string[];sessions:number}[]}catch{return[]}}
 private tail=Promise.resolve();
 async add(path:string,name?:string){const folder=await this.folder(path),label=name?.trim()||basename(folder);if(label.length>100)throw Error('项目名称不能超过 100 字');
  const p={path:folder,name:label,agents:['Codex','Hermes','Claude Code'],sessions:0};
  const save=this.tail.then(async()=>{const rows=await this.list(),index=rows.findIndex(r=>r.path===folder);if(index>=0)rows[index]=p;else rows.push(p);const f=join(this.dir,'folder-projects.json');await writeFile(f+'.tmp',JSON.stringify(rows),{mode:0o600});await rename(f+'.tmp',f)});
  this.tail=save.catch(()=>{});await save;return p;
 }
 async assign(id:string,path:string){
  const folder=await this.folder(path);const save=this.tail.then(async()=>{const f=join(this.dir,'folder-session-projects.json');let rows:Record<string,string>={};try{rows=JSON.parse(await readFile(f,'utf8'))}catch{}rows[id]=folder;await writeFile(f+'.tmp',JSON.stringify(rows),{mode:0o600});await rename(f+'.tmp',f)});this.tail=save.catch(()=>{});await save;
 }
 async contains(path:string){return(await this.list()).some(p=>p.path===path)}
}

// Persist an empty native thread in the chosen cwd, then let the desktop own its first turn.
export async function prepareFolderThread(root:string,cwd:string):Promise<string>{
 const child=spawn(process.env.ORBIT_CODEX_BIN||process.env.CODEX_CLI_PATH||(existsSync('/usr/lib/chatgpt/resources/codex')?'/usr/lib/chatgpt/resources/codex':'codex'),['app-server','--listen','stdio://'],{stdio:'pipe',env:codexEnvironment(root)});
 child.stderr.on('data',()=>{});let seq=0;let stage='启动';
 const pending=new Map<number,{resolve:(r:any)=>void;reject:(e:Error)=>void}>();
 const fail=(e:Error)=>{for(const p of pending.values())p.reject(e);pending.clear()};
 child.on('error',fail);child.on('exit',()=>fail(Error('Codex 创建连接已退出')));
 const lines=createInterface({input:child.stdout});lines.on('line',line=>{try{const m=JSON.parse(line),p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result)}}catch{}});
 const rpc=(method:string,params:any)=>new Promise<any>((resolve,reject)=>{stage=method;const id=++seq;pending.set(id,{resolve,reject});child.stdin.write(JSON.stringify({id,method,params})+'\n')});
 const timer=setTimeout(()=>{fail(Error('创建目录会话超时（'+stage+'），结果未知'));child.kill()},20000);
 try{await rpc('initialize',{clientInfo:{name:'gcollie_folder',version:'0.1.5'},capabilities:{}});child.stdin.write('{"method":"initialized"}\n');const r=await rpc('thread/start',{cwd,persistExtendedHistory:true});if(!r.thread?.id)throw Error('未返回原生会话编号');await rpc('thread/inject_items',{threadId:r.thread.id,items:[{type:'message',role:'developer',content:[{type:'input_text',text:'Project working directory: '+cwd}]}]});await rpc('thread/name/set',{threadId:r.thread.id,name:'新会话'});await rpc('thread/read',{threadId:r.thread.id,includeTurns:false});await rpc('thread/unsubscribe',{threadId:r.thread.id});return r.thread.id}finally{clearTimeout(timer);lines.close();child.kill()}
}
