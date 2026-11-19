import {collaboration} from './codex-options.js';
import {prepareAgentMedia} from './claude-media.js';
import{attachmentInput}from'./attachments.js';
import net from'node:net';import{join}from'node:path';import{homedir}from'node:os';import{lstatSync,readFileSync,writeFileSync,renameSync}from'node:fs';
export function applyDesktopPatches(state:any,patches:any[]){for(const p of patches){if(!Array.isArray(p.path)||p.path.some((x:any)=>['__proto__','prototype','constructor'].includes(String(x))))throw Error('无效增量路径');if(!p.path.length)throw Error('需要完整快照');let target=state;for(const key of p.path.slice(0,-1)){if(target==null||!Object.hasOwn(target,key))throw Error('增量路径缺失');target=target[key]}const key=p.path.at(-1);if(Array.isArray(target)){const i=Number(key);if(!Number.isInteger(i)||i<0||i>target.length)throw Error('数组增量越界');if(p.op==='remove')target.splice(i,1);else if(p.op==='add')target.splice(i,0,p.value);else if(p.op==='replace')target[i]=p.value;else throw Error('未知增量')}else if(target&&typeof target==='object'){if(p.op==='remove')delete target[key];else if(['add','replace'].includes(p.op))target[key]=p.value;else throw Error('未知增量')}else throw Error('无效增量目标')}return state}
// Codex host async questions are agentMessage.questions, not app-server requests.
// Mirror its exact question identity and reply envelope; never invent an RPC answer.
function desktopAsyncQuestion(c:any):any {
 const entities=c.turnHistory?.history?.entitiesByKey;
 const loaded=[...(Array.isArray(c.turns)?c.turns:[]),...Object.values(entities&&typeof entities==='object'?entities:{})] as any[];
 const turns=[...new Map(loaded.map((turn:any)=>[turn?.turnId??turn?.id??turn,turn])).values()];
 const answered=new Set<string>();
 const open='<send_user_message_question_reply>',close='</send_user_message_question_reply>';
 for(const turn of turns)for(const item of Array.isArray(turn?.items)?turn.items:[]){
  const content=item?.type==='userMessage'?item.content:item?.type==='steeringUserMessage'&&item.status==='accepted'?item.input:null;
  if(!Array.isArray(content)||content.length!==1||content[0]?.type!=='text'||typeof content[0].text!=='string')continue;
  const text=content[0].text.trim();
  if(!text.startsWith(open)||!text.endsWith(close))continue;
  try{
   const decoded=JSON.parse(text.slice(open.length,-close.length));
   const replies=Array.isArray(decoded)?decoded:[decoded];
   if(!replies.length||!replies.every((r:any)=>r&&typeof r.questionItemId==='string'&&typeof r.question==='string'&&typeof r.answer==='string'))continue;
   for(const reply of replies)answered.add(reply.questionItemId);
  }catch{}
 }
 for(const turn of [...turns].reverse()){
  if(turn?.status!=='inProgress'||typeof turn.turnId!=='string'||!turn.turnId)continue;
  for(const item of Array.isArray(turn.items)?turn.items:[]){
   if(item?.type!=='agentMessage'||typeof item.id!=='string'||!item.id||!Array.isArray(item.questions))continue;
   const questions=item.questions.flatMap((q:any,index:number)=>{
    if(!q||typeof q.title!=='string'||!q.title.trim()||!Array.isArray(q.options)||!q.options.every((o:any)=>typeof o==='string'))return [];
    const id=JSON.stringify(['request_user_input_async',item.id,index]);
    return answered.has(id)?[]:[{id,question:q.title}];
   });
   if(!questions.length)continue;
   return {id:Buffer.from(JSON.stringify(['request_user_input_async',turn.turnId,item.id,questions.map((q:any)=>q.id)])).toString('base64url'),
    kind:'unsupported',method:'request_user_input_async',turnId:turn.turnId,
    params:{reason:'电脑上有待回答的问题；此类宿主提问请在电脑处理。',questions}};
  }
 }
 return undefined;
}
export function desktopPending(c:any){const r=(c.requests||[]).find((r:any)=>r.params?.threadId===c.id&&['item/commandExecution/requestApproval','item/fileChange/requestApproval','item/tool/requestUserInput','item/permissions/requestApproval','mcpServer/elicitation/request','item/tool/requestOptionPicker'].includes(r.method));if(!r)return desktopAsyncQuestion(c);const p=r.params;const id=Buffer.from(JSON.stringify([r.id,r.method,p.turnId])).toString('base64url');return{id,kind:r.method==='item/tool/requestUserInput'?'question':['item/commandExecution/requestApproval','item/fileChange/requestApproval'].includes(r.method)?'approval':'unsupported',requestId:r.id,method:r.method,turnId:p.turnId,params:{command:p.command,reason:p.reason,grantRoot:p.grantRoot,availableDecisions:p.availableDecisions,questions:p.questions}}}
export function desktopAnswer(c:any,b:any){const p=desktopPending(c);if(!p||p.id!==b.pendingId)throw Error('请求已过期，请刷新');if(p.kind==='unsupported')throw Error('请在桌面处理此类请求');if(p.kind==='approval'){if(!['accept','decline'].includes(b.decision))throw Error('无效审批');if(p.params.availableDecisions?.length&&!p.params.availableDecisions.includes(b.decision))throw Error('桌面未提供此审批选项');return{method:p.method==='item/commandExecution/requestApproval'?'thread-follower-command-approval-decision':'thread-follower-file-approval-decision',params:{conversationId:c.id,requestId:p.requestId,decision:b.decision}}}const answers:Record<string,any>={};for(const q of p.params.questions||[]){const value=b.answers?.[q.id];if(typeof value!=='string'||!value.trim()||value.length>4000)throw Error('请回答所有问题');answers[q.id]={answers:[value]}}return{method:'thread-follower-submit-user-input',params:{conversationId:c.id,requestId:p.requestId,response:{answers}}}}
export function desktopView(c:any){const entities=c.turnHistory?.history?.entitiesByKey||{};const turns=c.turns?.length?c.turns:Object.values(entities);const active:any=[...turns].reverse().find((t:any)=>t.status==='inProgress');const runtime=c.threadRuntimeStatus;const flags=runtime?.activeFlags||[];const status=runtime?.type==='active'?(flags.some((f:string)=>/waiting/i.test(f))?'waiting':'running'):runtime?.type==='idle'||(runtime?.type==='systemError'&&!active&&!desktopPending(c))?'idle':'unknown';const u=c.latestTokenUsageInfo?.total;return{desktopLive:true,desktopExperimental:true,readOnly:true,pending:desktopPending(c),status:desktopPending(c)?'waiting':status,turnId:active?.turnId||active?.id,model:c.latestModel,usage:u?{input:u.inputTokens??u.input_tokens,output:u.outputTokens??u.output_tokens,cached:u.cachedInputTokens??u.cached_input_tokens,semantics:'includes-cache'}:undefined}}
export function desktopReceiptTurnId(r:any):string|undefined {
 const v=r?.result?.result??r?.result??r;
 const id=v?.turn?.id??v?.turnId??v?.turn_id??r?.turnId;
 return typeof id==='string'?id:undefined;
}
// Desktop 26.1111 uses stream v13 with the same snapshot/patch envelope as v11.
// Keep an explicit allowlist: unknown versions must not authorize controls.
export class DesktopBridge{
 private socket?:net.Socket;private connecting?:Promise<void>;private client='uninitialized';private buffer=Buffer.alloc(0);private pending=new Map<string,{resolve:(v:any)=>void;reject:(e:Error)=>void;timer:ReturnType<typeof setTimeout>}>();private followed=new Map<string,{owner:string;state?:any;revision?:number;at:number;ok:boolean}>();private ledger:Record<string,{state:string;result?:any}>={};
 constructor(private root:string,private notify:()=>void){try{this.ledger=JSON.parse(readFileSync(join(root,'desktop-ledger.json'),'utf8'))}catch{}}
 private save(){const p=join(this.root,'desktop-ledger.json');writeFileSync(p+'.tmp',JSON.stringify(this.ledger),{mode:0o600});renameSync(p+'.tmp',p)}
 private send(m:any){if(!this.socket?.writable)throw Error('桌面连接不可用');const b=Buffer.from(JSON.stringify(m)),h=Buffer.alloc(4);h.writeUInt32LE(b.length);this.socket.write(Buffer.concat([h,b]))}
 private request(method:string,params:any,version=1,owner?:string){const requestId=crypto.randomUUID();return new Promise<any>((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(requestId);reject(Error('桌面响应超时；操作结果未知，请勿重复提交'))},5000);this.pending.set(requestId,{resolve,reject,timer});try{this.send({type:'request',requestId,sourceClientId:this.client,version,method,params,targetClientId:owner,timeoutMs:4500})}catch(e){clearTimeout(timer);this.pending.delete(requestId);reject(e)}})}
 private followMessage(id:string,owner:string,following:boolean){this.send({type:'broadcast',method:'thread-stream-following-changed',sourceClientId:this.client,version:1,targetClientIds:[owner],params:{hostId:'local',conversationId:id,following}})}
 private async connect(){if(this.socket?.writable&&this.client!=='uninitialized')return;if(this.connecting)return this.connecting;this.connecting=(async()=>{const path=join(homedir(),'.codex/ipc/ipc.sock');for(const p of [join(homedir(),'.codex/ipc'),path]){const st=lstatSync(p);if(st.uid!==process.getuid?.()||(st.mode&0o022))throw Error('桌面 socket 权限不符合要求')}this.socket=net.createConnection(path);this.socket.on('data',b=>this.receive(b));this.socket.on('error',()=>{});this.socket.once('close',()=>{this.client='uninitialized';this.buffer=Buffer.alloc(0);for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('桌面已断开'))}this.pending.clear();for(const f of this.followed.values()){f.ok=false;delete f.state}this.notify()});await new Promise<void>((r,j)=>{const timer=setTimeout(()=>{this.socket?.destroy();j(Error('桌面连接超时'))},3000);this.socket!.once('connect',()=>{clearTimeout(timer);r()});this.socket!.once('error',e=>{clearTimeout(timer);j(e)})});const r=await this.request('initialize',{clientType:'orbit'},0);this.client=r.result.clientId})();try{await this.connecting}finally{this.connecting=undefined}}
 private receive(b:Buffer){this.buffer=Buffer.concat([this.buffer,b]);while(this.buffer.length>=4){const n=this.buffer.readUInt32LE(0);if(!n||n>64*1024*1024){this.socket?.destroy();return}if(this.buffer.length<n+4)return;let m;try{m=JSON.parse(this.buffer.subarray(4,n+4).toString())}catch{this.socket?.destroy();return}this.buffer=this.buffer.subarray(n+4);if(m.type==='response'){const p=this.pending.get(m.requestId);if(p){clearTimeout(p.timer);this.pending.delete(m.requestId);m.resultType==='success'?p.resolve(m):p.reject(Error(m.error||'桌面拒绝请求'))}}else if(m.type==='client-discovery-request'){this.send({type:'client-discovery-response',requestId:m.requestId,response:{canHandle:false}})}else if(m.type==='broadcast'&&m.method==='client-status-changed'&&m.params?.status==='disconnected'){for(const f of this.followed.values())if(f.owner===m.params.clientId){f.ok=false;delete f.state}this.notify()}else if(m.type==='broadcast'&&m.method==='thread-stream-state-changed'&&[11,13].includes(m.version)){const id=m.params?.conversationId,f=this.followed.get(id);if(!f||m.sourceClientId!==f.owner||m.params.hostId!=='local')continue;const c=m.params.change;try{if(c.type==='snapshot'){if(c.conversationState?.id!==id)throw Error('快照会话不匹配');f.state=c.conversationState;f.revision=c.revision}else if(c.type==='patches'){if(f.revision!==c.baseRevision||!f.state)throw Error('增量缺口');applyDesktopPatches(f.state,c.patches);f.revision=c.revision}else continue;f.ok=true;this.notify()}catch{f.ok=false;delete f.state;this.followMessage(id,f.owner,true)}}}}
 async follow(id:string){if(!/^[a-zA-Z0-9_-]+$/.test(id))throw Error('无效会话 ID');await this.connect();const existing=this.followed.get(id);if(existing?.ok){existing.at=Date.now();return}const r=await this.request('thread-owner-discovery',{hostId:'local',conversationId:id});const owner=r.handledByClientId;this.followed.set(id,{owner,at:Date.now(),ok:false});if(this.followed.size>5){const oldest=[...this.followed].sort((a,b)=>a[1].at-b[1].at)[0];this.followMessage(oldest[0],oldest[1].owner,false);this.followed.delete(oldest[0])}this.followMessage(id,owner,true);for(let i=0;i<30;i++){if(this.followed.get(id)?.ok)return;await new Promise(r=>setTimeout(r,50))}throw Error('未收到桌面快照')}
 view(id:string){const f=this.followed.get(id);return f?.ok&&f.state?desktopView(f.state):{desktopLive:false,readOnly:true,status:'unknown'}}
 receipts(id:string){return Object.entries(this.ledger).filter(([key,v])=>key.startsWith(id+':')&&v.state==='done').slice(-100).map(([key,v])=>({requestId:key.slice(id.length+1),turnId:desktopReceiptTurnId(v.result)})).filter(r=>r.turnId)}
 async action(id:string,b:any){if(typeof b.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(b.requestId))throw Error('无效操作编号');const key=id+':'+b.requestId;if(this.ledger[key]){const old=this.ledger[key];if(old.state==='done')return old.result;throw Error('操作已提交或结果未知，不重复发送')}await this.follow(id);if(this.ledger[key])throw Error('操作已提交，不重复发送');let f=this.followed.get(id)!,v=desktopView(f.state);if(b.action==='send'&&v.status==='unknown'){f.ok=false;await this.follow(id);f=this.followed.get(id)!;v=desktopView(f.state)}let method,params,version;
 if(b.action==='send'){const prepared=await prepareAgentMedia(b.text,b.attachments||[]);b={...b,text:prepared.text,attachments:prepared.files,mediaPrepared:true};const send=desktopSend(id,v,b);method=send.method;version=send.version;params=send.params}
 else if(b.action==='stop'){if(!v.turnId||v.turnId!==b.turnId)throw Error('桌面执行轮次已变化，请刷新');method='thread-follower-interrupt-turn';version=4;params={conversationId:id,mode:'user-stop',expectedTurnId:b.turnId}}
 else if(b.action==='answer'){const a=desktopAnswer(f.state,b);method=a.method;params=a.params;version=1}else throw Error('未知桌面操作');this.ledger[key]={state:'sending'};this.save();try{const r=await this.request(method,params,version,f.owner);const result={ok:true,result:r.result,turnId:desktopReceiptTurnId(r)};this.ledger[key]={state:'done',result};this.save();return result}catch(e){this.ledger[key]={state:'unknown'};this.save();throw e}}
 close(){for(const[id,f]of this.followed)try{this.followMessage(id,f.owner,false)}catch{}this.socket?.destroy()}
}

// Match the desktop composer: active turns accept steering via the owner.
export function desktopSend(id:string,v:any,b:any){const input=[...attachmentInput(b.text,b.attachments,b.mediaPrepared?64000:4000),...(b.skills||[])];if(v.status==='idle')return{method:'thread-follower-start-turn',version:2,params:{conversationId:id,turnStart:{request:{threadId:id,input,clientUserMessageId:b.requestId,...(b.mode&&(v.model||b.mode==='plan')?{collaborationMode:collaboration(b.mode,v.model)}:{})},context:{inheritThreadSettings:true}}}};if(['running','waiting'].includes(v.status)&&v.turnId)return{method:'thread-follower-steer-turn',version:1,params:{conversationId:id,input,clientUserMessageId:b.requestId,restoreMessage:{text:b.text,context:{}}}};throw Error('桌面执行状态尚未同步，请刷新后发送')}
