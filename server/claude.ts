import {historyPage} from './history.js';
import {claudeMediaInput} from './claude-media.js';
import type {Attachment} from './attachments.js';
import {dirname} from 'node:path';
import {spawn,type ChildProcess} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync,renameSync,existsSync} from 'node:fs';
import {readdir,readFile,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {homedir} from 'node:os';

const valid=(id:string)=>/^[a-f0-9]{8}-[a-f0-9-]{27,28}$/i.test(id);
export function claudeEvents(rows:any[],before?:string,all=false){
 const events:any[]=[];let usage={input:0,output:0,cached:0,semantics:'includes-cache'};const counted=new Set<string>();
 for(const r of rows){const m=r.message;if(!m||!['user','assistant'].includes(m.role)||r.isMeta||r.isSidechain||(r.type&&!['user','assistant'].includes(r.type)))continue;
  const parts=typeof m.content==='string'?[{type:'text',text:m.content}]:m.content||[];
  if(m.role==='user'){
   const media=parts.filter((p:any)=>p.type==='image'&&p.source?.type==='base64'&&/^image\/(jpeg|png|gif|webp)$/.test(p.source.media_type)).map((p:any)=>`data:${p.source.media_type};base64,${p.source.data}`);
   const text=parts.filter((p:any)=>p.type==='text').map((p:any)=>p.text).join('\n\n');
   if(text||media.length)events.push({id:r.uuid||String(events.length),role:'user',text:String(text).slice(0,24000),media,time:Date.parse(r.timestamp)||0});
  }
  for(let i=0;i<parts.length;i++){
   if(m.role==='user')continue;const p=parts[i];const role=p.type==='tool_result'||p.type==='tool_use'?'tool':m.role;
   const text=p.type==='text'?p.text:p.type==='tool_use'?'调用 '+p.name:p.type==='tool_result'?(typeof p.content==='string'?p.content:JSON.stringify(p.content)):'';
   if(text)events.push({id:(r.uuid||String(events.length))+':'+i,role,text:String(text).slice(0,24000),time:Date.parse(r.timestamp)||0});
  }
  if(m.usage&&!counted.has(m.id)){counted.add(m.id);const u=m.usage;usage.input+=(u.input_tokens||0)+(u.cache_read_input_tokens||0)+(u.cache_creation_input_tokens||0);usage.output+=u.output_tokens||0;usage.cached+=u.cache_read_input_tokens||0;}
 }
 return {...(all?{events}:historyPage(events,before)),usage};
}
export class ClaudeBridge{
 private owned:Record<string,any>={};private active=new Map<string,{child:ChildProcess;turnId:string;stopped?:boolean}>();private seen:Record<string,boolean>={};private submitting=new Set<string>();private cache:any[]=[];private expires=0;
 constructor(private dir:string,private change:()=>void,private root=join(homedir(),'.claude/projects'),private binary=process.env.GCOLLIE_CLAUDE_BIN||join(homedir(),'.local/bin/claude')){try{this.owned=JSON.parse(readFileSync(join(dir,'claude-sessions.json'),'utf8'))}catch{}for(const s of Object.values(this.owned))if(s.status==='running'){s.status='unknown';s.error='服务重启，上一轮结果未知；请先在终端确认'}try{this.seen=JSON.parse(readFileSync(join(dir,'claude-requests.json'),'utf8'))}catch{}}
 private save(){for(const [name,data]of [['claude-sessions',this.owned],['claude-requests',this.seen]] as const){const p=join(this.dir,name+'.json');writeFileSync(p+'.tmp',JSON.stringify(data),{mode:0o600});renameSync(p+'.tmp',p)}}
 async list(){if(Date.now()<this.expires)return this.cache;const found:any[]=[];try{for(const folder of await readdir(this.root,{withFileTypes:true})){if(!folder.isDirectory())continue;for(const f of await readdir(join(this.root,folder.name))){if(!f.endsWith('.jsonl')||!valid(f.slice(0,-6)))continue;const path=join(this.root,folder.name,f);const s=await stat(path);found.push({path,id:f.slice(0,-6),updatedAt:s.mtimeMs})}}}catch{}
  found.sort((a,b)=>b.updatedAt-a.updatedAt);const sessions:any[]=[];
  for(const f of found.slice(0,500)){try{const rows=(await readFile(f.path,'utf8')).split('\n').flatMap(l=>{try{return[JSON.parse(l)]}catch{return[]}});const first=rows.find(r=>r.message?.role==='user'&&!r.isMeta);const text=first?.message?.content;const title=typeof text==='string'?text:text?.find((p:any)=>p.type==='text')?.text;const cwd=rows.find(r=>r.cwd)?.cwd||'';sessions.push({id:'claude:'+f.id,nativeId:f.id,agent:'Claude Code',title:this.owned[f.id]?.title||title?.slice(0,80)||'Claude Code',cwd,projectPath:cwd||null,project:cwd.split('/').pop()||'无项目',updatedAt:f.updatedAt,archived:false,readOnly:!this.owned[f.id],status:'unknown',model:[...rows].reverse().find(r=>r.message?.model)?.message.model,_path:f.path})}catch{}}
  for(const [id,s]of Object.entries(this.owned))if(!sessions.some(v=>v.nativeId===id))sessions.push({id:'claude:'+id,nativeId:id,agent:'Claude Code',...s,projectPath:s.cwd||null,project:s.cwd.split('/').pop()||'无项目',archived:false});
  this.cache=sessions;this.expires=Date.now()+2000;return sessions;
 }
 async detail(id:string,options?:{before?:string;all?:boolean}){if(!valid(id))throw Error('无效 Claude Code 会话');const s=(await this.list()).find(v=>v.nativeId===id);if(!s)throw Error('Claude Code 会话不存在');let rows:any[]=[];if(s._path)rows=(await readFile(s._path,'utf8')).split('\n').flatMap(l=>{try{return[JSON.parse(l)]}catch{return[]}});const {_path,...summary}=s;const a=this.active.get(id);const owned=this.owned[id];return{...summary,...claudeEvents(rows,options?.before,options?.all),claudeLive:!!owned,desktopLive:!!owned,desktopControl:!!owned,readOnly:!owned,status:a?'running':owned?.status||'unknown',turnId:a?.turnId,desktopError:owned?.error||(!owned?'终端会话仅查看历史；请在终端继续，或在 G-Collie 新建会话':undefined),connectionState:owned?'connected':'readonly'};}
 async create(title:string,cwd:string,prompt?:string,files:Attachment[]=[]){if(!existsSync(this.binary))throw Error('本机未安装 Claude Code CLI');const id=randomUUID();this.owned[id]={title,cwd,updatedAt:Date.now(),status:'idle',started:false};this.save();this.expires=0;if(prompt?.trim()||files.length)await this.action(id,{action:'send',text:prompt||'',attachments:files,requestId:randomUUID()});this.change();return{id:'claude:'+id};}
 async action(id:string,b:any){if(!valid(id)||!this.owned[id])throw Error('仅能控制 G-Collie 创建的 Claude Code 会话');const a=this.active.get(id);
  if(b.action==='stop'){if(!a||b.turnId!==a.turnId)throw Error('执行轮次已改变，请刷新');a.stopped=true;a.child.kill('SIGTERM');const timer=setTimeout(()=>{if(this.active.get(id)===a)a.child.kill('SIGKILL')},3000);timer.unref();return{ok:true};}
  if(b.action!=='send')throw Error('Claude Code 暂支持发送与停止');if(a||this.submitting.has(id))throw Error('当前会话正在执行');if(typeof b.text!=='string'||(!b.text.trim()&&!b.attachments?.length)||b.text.length>4000)throw Error('请输入消息');if(typeof b.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(b.requestId))throw Error('无效操作编号');const key=id+':'+b.requestId;if(this.seen[key])throw Error('此消息已提交，请刷新确认');
  this.submitting.add(id);let input:any;try{input=await claudeMediaInput(b.text,b.attachments||[]);input.message.content=input.message.content.map(({_path,...part}:any)=>part)}finally{this.submitting.delete(id)}
  this.seen[key]=true;const s=this.owned[id];s.status='running';s.error=undefined;this.save();const args=['-p','--input-format','stream-json','--output-format','stream-json','--verbose','--permission-mode','dontAsk',...(s.started?['--resume',id]:['--session-id',id])];
  for(const folder of new Set<string>((b.attachments||[]).map((f:Attachment)=>dirname(f.path))))args.push('--add-dir',folder);
  const child=spawn(this.binary,args,{cwd:s.cwd,env:process.env,stdio:['pipe','pipe','pipe']});const turn={child,turnId:randomUUID(),stopped:false};this.active.set(id,turn);let buffer='',result:any;
  child.stdout!.on('data',chunk=>{buffer+=chunk;let i;while((i=buffer.indexOf('\n'))>=0){const l=buffer.slice(0,i);buffer=buffer.slice(i+1);try{const r=JSON.parse(l);if(r.type==='system'&&r.subtype==='init')s.started=true;if(r.type==='result')result=r}catch{}}this.expires=0;this.change()});child.stderr!.on('data',()=>{});
  const finish=(code:number|null,spawnError?:Error)=>{if(this.active.get(id)!==turn)return;this.active.delete(id);s.status=turn.stopped?'interrupted':code===0&&!result?.is_error?'idle':'failed';s.error=spawnError?'无法启动 Claude Code，请检查安装路径':result?.is_error?String(result.result||'模型请求失败'):code!==0&&!turn.stopped?'Claude Code 执行失败，请在终端检查配置':result?.permission_denials?.length?'部分工具需要授权，请在电脑终端继续处理':undefined;s.updatedAt=Date.now();this.save();this.expires=0;this.change()};child.once('error',e=>finish(null,e));child.once('close',code=>finish(code));child.stdin!.on('error',()=>{});child.stdin!.end(JSON.stringify({...input,session_id:id,parent_tool_use_id:null})+'\n');this.change();return{ok:true,turnId:turn.turnId};
 }
 close(){for(const a of this.active.values())a.child.kill('SIGTERM')}
}
