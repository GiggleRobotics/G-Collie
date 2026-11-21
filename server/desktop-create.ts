import net from 'node:net';
import {lstatSync,readFileSync,writeFileSync,renameSync,readdirSync} from 'node:fs';
import {join} from 'node:path';
import {createNotSubmitted,SessionCreateError} from './session-create.js';

type PreparedThread={threadId:string;cwd:string};
type Checkpoint={prepared?:PreparedThread;savePrepared:(threadId:string)=>void};
export class DesktopCreator {
 private runtime:{pipe?:string;context?:string}={};private discovering?:Promise<string>;
 private ledger:Record<string,any>={};private busy=new Set<string>();
 constructor(private root:string,private folderStart?:(cwd:string,b:any)=>Promise<any>,private independentStart?:(b:any,checkpoint:Checkpoint)=>Promise<any>){try{this.runtime=JSON.parse(readFileSync(join(root,'desktop-runtime.json'),'utf8'))}catch{}if(process.env.CODEX_APP_TOOLS_PIPE_PATH&&process.env.CODEX_THREAD_ID){this.runtime={pipe:process.env.CODEX_APP_TOOLS_PIPE_PATH,context:process.env.CODEX_THREAD_ID};writeFileSync(join(root,'desktop-runtime.json'),JSON.stringify(this.runtime),{mode:0o600})}try{this.ledger=JSON.parse(readFileSync(join(root,'desktop-create-ledger.json'),'utf8'))}catch{}}
 private save(){const p=join(this.root,'desktop-create-ledger.json');writeFileSync(p+'.tmp',JSON.stringify(this.ledger),{mode:0o600});renameSync(p+'.tmp',p)}
 private rpcAt(path:string,method:string,params:any,timeout=60000):Promise<any>{const st=lstatSync(path);if(!st.isSocket()||st.uid!==process.getuid?.()||(st.mode&0o077))throw Error('Codex 桌面接口权限异常');return new Promise((resolve,reject)=>{const socket=net.connect(path);let buffer=Buffer.alloc(0);const timer=setTimeout(()=>finish(Error('Codex 桌面响应超时，结果未知，请勿重复创建')),timeout);function finish(error?:Error,result?:any){clearTimeout(timer);socket.destroy();error?reject(error):resolve(result)}socket.on('connect',()=>{const body=Buffer.from(JSON.stringify({jsonrpc:'2.0',id:1,method,params})),h=Buffer.alloc(4);h.writeUInt32LE(body.length);socket.write(Buffer.concat([h,body]))});socket.on('error',e=>finish(e));socket.on('end',()=>finish(Error('Codex 桌面连接关闭，结果可能未知')));socket.on('data',chunk=>{buffer=Buffer.concat([buffer,chunk]);if(buffer.length<4)return;const n=buffer.readUInt32LE();if(n>16*1024*1024){finish(Error('桌面响应过大'));return}if(buffer.length<n+4)return;try{const r=JSON.parse(buffer.subarray(4,n+4).toString());r.error?finish(Error(r.error.message)):finish(undefined,r.result)}catch(e){finish(e as Error)}})})}
 private toolsDirectories(){
  const uid=process.getuid?.();
  // Current Linux releases have a distinct socket for desktop tools.
  return [process.platform==='linux'&&uid!==undefined?'/tmp/codex-app-tools-'+uid:'/tmp/codex-app-tools','/tmp/codex-browser-use'];
 }
 private async checkTools(path:string,timeout:number){
  try{
   const r=await this.rpcAt(path,'tools/list',{threadStartKind:'all'},timeout);
   return r.tools?.some((t:any)=>t.name==='create_thread');
  }catch{return false}
 }
 private async pipe(){
  const cached=this.runtime.pipe;
  if(cached&&await this.checkTools(cached,1500))return cached;
  if(this.discovering)return this.discovering;
  this.discovering=(async()=>{
   for(const directory of this.toolsDirectories()){
    let names:string[];
    try{
     const st=lstatSync(directory);
     if(!st.isDirectory()||st.uid!==process.getuid?.()||(st.mode&0o022))continue;
     names=readdirSync(directory).filter(n=>/^[a-f0-9-]+\.sock$/.test(n)).slice(0,30);
    }catch{continue}
    const matches:string[]=[];
    for(const name of names){
     const path=join(directory,name);
     if(await this.checkTools(path,700))matches.push(path);
    }
    if(matches.length>1)break;
    if(matches.length===1){
     this.runtime.pipe=matches[0];
     writeFileSync(join(this.root,'desktop-runtime.json'),JSON.stringify(this.runtime),{mode:0o600});
     return matches[0];
    }
   }
   throw Error('未唯一发现 Codex 桌面接口，请先确认 Codex 桌面 App 正在运行');
  })();
  try{return await this.discovering}finally{this.discovering=undefined}
 }
 private async rpc(method:string,params:any){return this.rpcAt(await this.pipe(),method,params)}
 private async tool(tool:string,args:any){const threadId=(tool==='navigate_to_codex_page'?args.threadId:undefined)||this.runtime.context;if(!threadId)throw Error('缺少 Codex 桌面初始化信息，请先在 Codex 环境运行后台安装命令');const r=await this.rpc('tools/call',{namespace:'codex_app',tool,arguments:args,callerSource:'codex',hostId:'local',threadId,callId:'orbit-'+crypto.randomUUID(),turnId:crypto.randomUUID()});if(!r.success)throw Error(r.contentItems?.filter((x:any)=>x.type==='inputText').map((x:any)=>x.text).join('\n')||'桌面操作失败');const texts=r.contentItems?.filter((x:any)=>x.type==='inputText').map((x:any)=>x.text)||[];for(const t of texts){try{return JSON.parse(t)}catch{}}throw Error('桌面返回无法识别的结果')}
 async usageLimits(){
  // Desktop login/runtime may change while this service stays alive. Reload
  // persisted discovery before this read; never replay mutations on recovery.
  try{const runtime=JSON.parse(readFileSync(join(this.root,'desktop-runtime.json'),'utf8'));if(typeof runtime.pipe==='string'&&typeof runtime.context==='string')this.runtime={pipe:runtime.pipe,context:runtime.context}}catch{}
  try{return await this.tool('get_usage_limits',{})}catch(error){
   if(/429|rate.limit/i.test(String(error)))throw error;
   // Force discovery for the next read. Only this idempotent query is retried.
   this.runtime.pipe=undefined;
   return this.tool('get_usage_limits',{});
  }
 }
 async status(){try{await this.pipe();return{available:true,experimental:true}}catch(e){return{available:false,experimental:true,reason:(e as Error).message}}}
 async firstMessage(threadId:string,prompt:string){return this.tool('send_message_to_thread',{threadId,prompt})}
 async load(threadId:string){if(!/^[a-zA-Z0-9_-]+$/.test(threadId))throw Error('无效会话编号');return this.tool('navigate_to_codex_page',{threadId})}
 private async startIndependent(b:any,old:any){
  const id=b.requestId;
  let prepared:PreparedThread|undefined=old?.prepared?.cwd===(b.cwd||'')?old.prepared:undefined;
  this.ledger[id]={state:'sending',prepared};
  this.save();
  try{
   const result=await this.independentStart!(b,{prepared,savePrepared:threadId=>{
    prepared={threadId,cwd:b.cwd||''};
    this.ledger[id]={state:'sending',prepared};
    this.save();
   }});
   if(!result.threadId)throw Error('未返回会话编号，结果未知');
   const value={id:'codex:'+result.threadId,nativeId:result.threadId,...(result.turnId?{turnId:result.turnId}:{})};
   this.ledger[id]={state:'done',result:value};
   this.save();
   return value;
  }catch(e){
   this.ledger[id]={state:e instanceof SessionCreateError&&e.outcome==='failed'?'failed':'unknown',prepared};
   this.save();
   throw e;
  }
 }
 async create(b:any){if(typeof b.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(b.requestId))throw createNotSubmitted(Error('无效操作编号'));if(typeof b.prompt!=='string'||!b.prompt.trim()||b.prompt.length>64000)throw createNotSubmitted(Error('请输入 1–4000 字首条消息'));if(this.busy.has(b.requestId))throw Error('正在创建，请稍候');const old=this.ledger[b.requestId];if(old?.state==='done')return old.result;if(old&&old.state!=='failed')throw Error('新建结果未知，请先刷新列表，勿重复创建');this.busy.add(b.requestId);try{if(this.independentStart)return await this.startIndependent(b,old);const catalog=await this.tool('list_projects',{});const projects=Array.isArray(catalog)?catalog:catalog.projects;let target:any={type:'projectless'};if(b.cwd){const p=projects?.find((p:any)=>p.hostId==='local'&&p.projectKind==='local'&&(p.path===b.cwd||p.rootPaths?.includes(b.cwd)||p.workspaceRoot===b.cwd));if(!p&&!b.folderSelected)throw Error('未找到对应的 Codex 本地项目，请刷新项目列表');if(p)target={type:'project',projectId:p.projectId||p.id,environment:{type:'local'}};else if(!this.folderStart)throw Error('目录项目创建尚未连接');else target={type:'folder',cwd:b.cwd}}this.ledger[b.requestId]={state:'sending'};this.save();try{const result=target.type==='folder'?await this.folderStart!(b.cwd,b):await this.tool('create_thread',{title:b.title,prompt:b.prompt.trim(),target});if(!result.threadId)throw Error('桌面创建尚未返回会话编号，请刷新列表确认');const value={id:'codex:'+result.threadId,nativeId:result.threadId,...(result.turnId?{turnId:result.turnId}:{})};this.ledger[b.requestId]={state:'done',result:value};this.save();return value}catch(e){this.ledger[b.requestId]={state:'unknown'};this.save();throw e}}finally{this.busy.delete(b.requestId)}}
}
