import {prepareAgentMedia} from './claude-media.js';
import {readFile,lstat,realpath} from 'node:fs/promises';
import {createConnection} from 'node:net';
import {homedir} from 'node:os';
import{attachmentInput}from'./attachments.js';
import{execFile}from'node:child_process';import{promisify}from'node:util';import{readFileSync,writeFileSync,renameSync}from'node:fs';import{join}from'node:path';
const exec=promisify(execFile);
/** Same-user gateway bootstrap. Credentials stay local and every grant is used once. */
export async function hermesGatewayTicket(origin:string,purpose:'interactive'|'native-http',home=process.env.HERMES_HOME||join(homedir(),'.hermes')){
 const uid=process.getuid?.();if(uid===undefined)throw Error('当前系统不支持 Hermes 本机凭据接入');
 const root=await realpath(home),socket=join(root,'gateway.sock');
 const directory=await lstat(root),node=await lstat(socket);
 if(!directory.isDirectory()||directory.uid!==uid||(directory.mode&0o022)||!node.isSocket()||node.uid!==uid||(node.mode&0o077))throw Error('Hermes 本机控制入口权限不安全');
 async function query(verb:string,params?:any):Promise<any>{return new Promise((resolve,reject)=>{
  const client=createConnection(socket);client.setEncoding('utf8');let body='',done=false;
  const finish=(error?:Error,result?:any)=>{if(done)return;done=true;client.destroy();error?reject(error):resolve(result)};
  client.setTimeout(4000,()=>finish(Error('Hermes 本机控制入口超时')));
  client.on('error',()=>finish(Error('Hermes 本机控制入口不可用')));
  client.on('connect',()=>client.write(JSON.stringify({protocol:1,verb,id:1,...params?{params}:{}})+'\n'));
  client.on('data',chunk=>{body+=chunk;if(Buffer.byteLength(body)>524288)return finish(Error('Hermes 本机控制响应过大'));if(!body.includes('\n'))return;try{const r=JSON.parse(body.split('\n')[0]);if(r.protocol!==1||r.id!==1||r.ok!==true||!r.result||typeof r.result!=='object')throw Error();finish(undefined,r.result)}catch{finish(Error('Hermes 本机控制响应无效或请求被拒绝'))}});
  client.on('end',()=>{if(!done)finish(Error('Hermes 本机控制响应不完整'))});
 })}
 const identity=await query('identify');
 if(identity.api_origin!==origin||identity.runtime_protocol!==1||typeof identity.instance_id!=='string'||!identity.instance_id)throw Error('Hermes 本机后端与控制入口不匹配');
 const profiles=Array.isArray(identity.served_profiles)?identity.served_profiles.filter((p:any)=>p?.home===root&&typeof p.profile_id==='string'&&p.profile_id):[];
 if(profiles.length!==1)throw Error('未唯一确定 Hermes 当前用户配置');
 const grant=await query('session-ticket',{instance_id:identity.instance_id,profile_id:profiles[0].profile_id,purpose});
 if(typeof grant.ticket!=='string'||! /^[A-Za-z0-9_-]{16,256}$/.test(grant.ticket))throw Error('Hermes 未返回有效的本机连接凭据');
 return grant.ticket as string;
}
/** Gateway v1 uses generation fences and structured approval RPCs, not the sidecar API. */
export function hermesGatewaySnapshot(raw:any){
 if(typeof raw?.running!=='boolean'||(!Number.isSafeInteger(raw.execution_generation)||raw.execution_generation<0))throw Error('Hermes 当前后端返回的会话状态不受支持');
 const prompts=Array.isArray(raw.prompts)?raw.prompts:[];
 return{...raw,nativeGateway:true,turn_started_at:raw.execution_generation,
  open_requests:[...prompts.map((p:any)=>({id:p.prompt_id,method:p.kind==='approval'?'approval':p.kind==='clarify'?'clarify':'unsupported',params:p})),
   ...(raw.open_requests||[])]};
}
export function hermesGatewayAnswer(raw:any,b:any,sessionId:string){
 const prompt=raw.prompts?.find((p:any)=>p.prompt_id===b.pendingId);if(!prompt)throw Error('此新版 Hermes 请求需在电脑处理，或请求已过期');
 if(prompt.execution_generation!==raw.execution_generation)throw Error('请求轮次已变化，请刷新后回答');
 const answer=hermesAnswer(raw,b).result;
 const common={session_id:sessionId,execution_generation:prompt.execution_generation,prompt_id:prompt.prompt_id};
 if(prompt.kind==='approval')return{method:'approval.respond',params:{...common,choice:answer.choice}};
 if(prompt.kind==='clarify')return{method:'clarify.respond',params:{...common,answer:answer.answer}};
 throw Error('此新版 Hermes 请求暂不支持，请在电脑处理');
}
export function hermesPending(raw:any){const r=raw.open_requests?.[0];if(!r)return undefined;const p=r.params||{};let kind=r.method==='approval'?'approval':r.method==='clarify'?'question':['sudo','secret'].includes(r.method)?'secret':'unsupported';const questions=(p.questions?.length?p.questions:[{qid:'answer',question:p.question||'请回答 Agent 的问题',choices:p.choices,multi_select:p.multi_select}]);return{id:r.id,kind,params:kind==='approval'?{command:p.command,reason:p.description,availableDecisions:Array.isArray(p.choices)?['accept','decline'].filter(d=>p.choices.includes(d==='accept'?'once':'deny')):undefined}:kind==='secret'?{command:p.command,prompt:r.method==='sudo'?'请输入电脑 sudo 密码以继续；可取消本次请求':p.prompt||('请输入 '+p.env_var),secretType:r.method}:kind==='question'?{questions:questions.map((q:any)=>({id:q.qid,question:q.question,multiSelect:!!q.multi_select,options:q.choices?.map((label:string)=>({label,description:''}))}))}:{}}}
export function hermesAnswer(raw:any,b:any){const r=raw.open_requests?.find((r:any)=>r.id===b.pendingId);if(!r)throw Error('请求已过期');const p=r.params||{};if(['sudo','secret'].includes(r.method)){if(typeof b.value!=='string'||b.value.length>4000)throw Error('请输入有效内容或取消');return{id:r.id,result:{value:b.value}}}if(r.method==='approval'){if(!['accept','decline'].includes(b.decision))throw Error('无效审批');const choice=b.decision==='accept'?'once':'deny';if(Array.isArray(p.choices)&&!p.choices.includes(choice))throw Error('Hermes 未提供此审批选项');return{id:r.id,result:{choice}}}if(r.method==='clarify'){const questions=p.questions?.length?p.questions:[{qid:'answer',multi_select:p.multi_select}];const answers:Record<string,string>={};for(const q of questions){let value=b.answers?.[q.qid];if(q.multi_select){let choices;try{choices=typeof value==='string'?JSON.parse(value):value}catch{throw Error('请选择有效答案')}if(!Array.isArray(choices)||!choices.length||choices.length>100||choices.some((v:any)=>typeof v!=='string'||!v.trim()||v.length>4000)||new Set(choices).size!==choices.length)throw Error('请选择有效答案');value=JSON.stringify(choices)}if(typeof value!=='string'||!value.trim()||value.length>4000)throw Error('请回答所有问题');answers[q.qid]=value}return{id:r.id,result:p.questions?.length?{answers}:{answer:answers.answer}}}throw Error('此 Hermes 请求暂不支持')}
export function hermesManagePatch(b:any){if(typeof b.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(b.requestId))throw Error('无效操作编号');if(b.action==='rename'){const title=typeof b.title==='string'?b.title.trim():'';if(!title||title.length>100)throw Error('请输入 1–100 字会话名称');return{title}}if(b.action==='archive')return{hidden:true};throw Error('未知操作')}
/** Reconcile the cumulative live buffer with this turn only, never global text dedupe. */
export function mergeHermesDetail(detail:any,live:any){
 const result={...detail,...live}, inflight=live.liveInflight;
 if(!inflight||typeof inflight.assistant!=='string'||!inflight.assistant)return result;
 const started=Number(live.turnId), start=started<1e12?started*1000:started;
 if(!Number.isFinite(start)||start<=0)return result;
 const events=[...(detail.events||[])];
 const anchors=[inflight.user,...(Array.isArray(inflight.corrections)?inflight.corrections:[])];
 // Hermes offsets are Python Unicode code points, not JavaScript UTF-16 units.
 const chars=Array.from(inflight.assistant);
 const offsets=[0,...(Array.isArray(inflight.correction_offsets)?inflight.correction_offsets:[]),chars.length];
 // Missing boundaries cannot safely place old output around a mid-turn correction.
 if(offsets.length!==anchors.length+1||offsets.some((n:any,i:number)=>!Number.isInteger(n)||n<0||n>chars.length||(i>0&&n<offsets[i-1])))return result;
 let search=0;
 for(let segment=0;segment<anchors.length;segment++){
  const anchor=events.findIndex((e:any,i:number)=>i>=search&&e.role==='user'&&typeof e.text==='string'&&e.text.trim()===String(anchors[segment]||'').trim()&&Number(e.time)>=start-2000);
  if(anchor<0)return result;
  search=anchor+1;
  let end=events.findIndex((e:any,i:number)=>i>anchor&&e.role==='user');if(end<0)end=events.length;
  let remainder=chars.slice(offsets[segment],offsets[segment+1]).join('');
  let matched=false;
  for(let n=anchor+1;n<end;n++){
   const event=events[n];if(event.role!=='assistant'||!event.text)continue;
   const text=String(event.text);const candidate=remainder.trimStart();
   if(candidate.startsWith(text.trim())){remainder=candidate.slice(text.trim().length);matched=true;}
   // A persisted completion may be ahead of the slightly older live snapshot.
   else if(text.trim().startsWith(candidate.trim())&&candidate.trim()){remainder='';matched=true;}
   else if(!matched){remainder='';break;} // Do not repaint an ambiguous structured turn.
  }
  if(remainder.trim())events.splice(end,0,{id:`hermes-live:${live.turnId}:${segment}`,role:'assistant',text:remainder,media:[],time:start,turnId:live.turnId});
 }
 // Every known live segment was handled in chronology; clients must not append the flat dump.
 result.events=events;result.liveInflight={...inflight,assistant:undefined};return result;
}
export class HermesBridge{
 private socket?:WebSocket;private token='';private ready?:Promise<void>;private seq=0;private pending=new Map<string,{resolve:(v:any)=>void;reject:(e:Error)=>void;timer:ReturnType<typeof setTimeout>}>();private ledger:Record<string,any>={};private busy=new Set<string>();private origin='';private nativeAuth=false;private closed=false;private gatewayStates=new Map<string,{epoch:string;seq:number;generation:number;prompts:any[];complete:boolean}>();
 constructor(private root:string,private notify:()=>void){try{this.ledger=JSON.parse(readFileSync(join(root,'hermes-ledger.json'),'utf8'))}catch{}}
 private save(){const p=join(this.root,'hermes-ledger.json');writeFileSync(p+'.tmp',JSON.stringify(this.ledger),{mode:0o600});renameSync(p+'.tmp',p)}
 private async discover(){if(process.env.ORBIT_HERMES_URL){const u=new URL(process.env.ORBIT_HERMES_URL);if(u.protocol!=='http:'||u.hostname!=='127.0.0.1'||u.username||u.password)throw Error('仅支持本机回环 Hermes 后端');return u.origin}const{stdout}=await exec('ss',['-ltnpH'],{timeout:3000});const ports=stdout.split('\n').filter(l=>/users:\(\("hermes"/.test(l)).map(l=>l.match(/127\.0\.0\.1:(\d+)/)?.[1]).filter(Boolean);if(ports.length!==1)throw Error('未唯一发现 Hermes 本机后端');return'http://127.0.0.1:'+ports[0]}
 private async connect(){if(this.socket?.readyState===WebSocket.OPEN)return;if(this.ready)return this.ready;this.ready=(async()=>{this.origin=await this.discover();const status=await(await fetch(this.origin+'/api/status',{signal:AbortSignal.timeout(4000)})).json();if(status.auth_required)throw Error('Hermes 要求登录，请通过其正常登录流程接入');const html=await(await fetch(this.origin+'/',{signal:AbortSignal.timeout(4000)})).text();const match=html.match(/window\.__HERMES_SESSION_TOKEN__\s*=\s*("[^"]+")/);this.nativeAuth=!match;const token=match?JSON.parse(match[1]):await hermesGatewayTicket(this.origin,'interactive');this.token=match?token:'';const ws=this.socket=this.nativeAuth?new WebSocket(this.origin.replace('http:','ws:')+'/api/ws',['hermes-gateway-v1','hermes-gateway-ticket.'+token]):new WebSocket(this.origin.replace('http:','ws:')+'/api/ws?token='+encodeURIComponent(token));ws.onmessage=({data})=>{for(const line of String(data).split('\n')){if(!line.trim())continue;let m;try{m=JSON.parse(line)}catch{continue}if(m.id!==undefined&&!m.method){const p=this.pending.get(String(m.id));if(p){this.pending.delete(String(m.id));clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result)}}else this.notify()}};ws.onclose=()=>{this.ready=undefined;this.gatewayStates.clear();for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Hermes 后端已断开，操作结果可能未知'))}this.pending.clear();this.notify()};await new Promise<void>((r,j)=>{const timer=setTimeout(()=>{ws.close();j(Error('Hermes 连接超时'))},6000);ws.onopen=()=>{clearTimeout(timer);r()};ws.onerror=()=>{clearTimeout(timer);j(Error('Hermes 连接失败'))}});await this.rpc('client.capabilities',{server_requests:true})})();try{await this.ready}catch(e){this.socket?.close();this.ready=undefined;throw e}}
 private rpc(method:string,params:any={}):Promise<any>{if(this.socket?.readyState!==WebSocket.OPEN)return Promise.reject(Error('Hermes 未连接'));const id='orbit-'+ ++this.seq;return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(id);reject(Error('Hermes 响应超时；请勿重复提交'))},20000);this.pending.set(id,{resolve,reject,timer});this.socket!.send(JSON.stringify({jsonrpc:'2.0',id,method,params}))})}
 async active(){await this.connect();const r=await this.rpc('session.active_list');return r.sessions||[]}
 async snapshot(key:string,attach=false){if(!/^[a-zA-Z0-9_-]+$/.test(key))throw Error('无效 Hermes 会话 ID');const sessions=await this.active();const row=sessions.find((s:any)=>s.session_key===key);if(!row)throw Error('此会话未在 Hermes 桌面后端加载，请先在电脑打开它');const raw=this.nativeAuth?(attach?this.rememberGateway(row.id,await this.rpc('session.resume',{session_id:row.id,omit_messages:true})):await this.readGateway(row.id,row)):await this.rpc('session.activate',{session_id:row.id,omit_messages:true});return{row,raw}}
 async load(key:string){if(!/^[a-zA-Z0-9_-]+$/.test(key))throw Error('无效会话编号');const rows=await this.active();if(!this.nativeAuth&&rows.some((r:any)=>r.session_key===key))return key;const r=await this.rpc('session.resume',this.nativeAuth?{session_id:key,omit_messages:true}:{session_id:key,source:'desktop',omit_messages:true,defer_history:true,close_on_disconnect:false});const resumed=r.session_key||r.resumed||(this.nativeAuth?r.session_id:undefined);if(!resumed)throw Error('Hermes 未返回恢复后的会话编号');if(this.nativeAuth)this.rememberGateway(resumed,r);return resumed}
 private rememberGateway(id:string,reply:any){
  const raw=hermesGatewaySnapshot(reply);
  if(typeof reply.replay_epoch==='string'&&Number.isSafeInteger(reply.last_sequence))this.gatewayStates.set(id,{epoch:reply.replay_epoch,seq:reply.last_sequence,generation:reply.execution_generation,prompts:reply.prompts||[],complete:true});
  return raw;
 }
 private async gatewayMetadata(id:string){const ticket=await hermesGatewayTicket(this.origin,'native-http');const response=await fetch(this.origin+'/api/sessions/'+encodeURIComponent(id),{headers:{'x-hermes-gateway-ticket':ticket},signal:AbortSignal.timeout(5000)});if(!response.ok)throw Error('Hermes 会话状态读取失败');return await response.json() as any;}
 private async readGateway(id:string,row:any){
  if(!['idle','working','waiting','starting'].includes(row.status))throw Error('Hermes 运行状态无法确认，请刷新');
  const info=await this.rpc('session.info',{session_id:id});
  const metadata=await this.gatewayMetadata(id);
  if(metadata.id!==id||!Number.isSafeInteger(metadata.runtime_generation)||metadata.runtime_generation<0)throw Error('Hermes 会话轮次无法确认');
  const generation=metadata.runtime_generation;let state=this.gatewayStates.get(id);
  if(state&&state.generation!==generation)state={...state,generation,prompts:[]};
  let replay=await this.rpc('session.events.since',{session_id:id,last_sequence:state?.seq||0,...state?{replay_epoch:state.epoch}:{}});
  if(!state&&replay.snapshot_required&&typeof replay.replay_epoch==='string')replay=await this.rpc('session.events.since',{session_id:id,last_sequence:0,replay_epoch:replay.replay_epoch});
  if(typeof replay.replay_epoch!=='string'||!Number.isSafeInteger(replay.last_sequence)||!Array.isArray(replay.events)||!Array.isArray(replay.open_requests))throw Error('Hermes 实时事件状态无效');
  const complete=!replay.snapshot_required&&(state?.complete??true);
  const prompts=new Map<string,any>((replay.snapshot_required?[]:state?.prompts||[]).map(p=>[p.prompt_id,p]));
  for(const event of replay.events){
   if(event.session_id!==id||event.execution_generation!==generation)continue;
   const payload=event.payload||{};
   if(['approval.request','clarify.request'].includes(event.type)&&typeof payload.prompt_id==='string'&&payload.execution_generation===generation)prompts.set(payload.prompt_id,payload);
   if(['approval.settled','clarify.settled'].includes(event.type))prompts.delete(payload.prompt_id);
  }
  const current=[...prompts.values()].filter(p=>p.execution_generation===generation);
  this.gatewayStates.set(id,{epoch:replay.replay_epoch,seq:replay.last_sequence,generation,prompts:current,complete});
  return hermesGatewaySnapshot({...info,nativeGateway:true,running:['working','waiting'].includes(row.status),status:row.status,execution_generation:generation,prompts:current,open_requests:replay.open_requests,replay_epoch:replay.replay_epoch,replayComplete:complete});
 }
 async view(key:string){
  const{row,raw}=await this.snapshot(key);const running=!!raw.running;const pending=hermesPending(raw);const launch=raw.launch_request||raw.info?.launch_request||{};const privateInput=launch.ignore_user_config!==true&&launch.safe_mode!==true;
  if(pending&&this.nativeAuth)Object.assign(pending,{generation:raw.execution_generation,requestEpoch:raw.replay_epoch});
  return{desktopLive:true,hermesLive:true,desktopControl:true,readOnly:false,status:pending||raw.status==='waiting'?'waiting':running?'running':raw.status==='starting'||raw.hydrating||raw.status==='resuming'||raw.pending?.some((p:any)=>p.status==='queued')?'starting':'idle',turnId:running&&Number.isSafeInteger(raw.turn_started_at)?String(raw.turn_started_at):undefined,model:row.model,...(this.nativeAuth?{gatewayCapabilities:{textSend:true,stop:true,answer:true,images:true,secrets:privateInput},...(raw.replayComplete===false?{desktopError:'实时事件记录不完整，请重新连接此会话同步审批状态'}:{})}:{}),pending,liveInflight:running?raw.inflight:undefined}
 }

 async create(b:any){if(typeof b.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(b.requestId))throw Error('无效操作编号');const id='create:'+b.requestId;const old=this.ledger[id];if(old){if(old.state==='done')return old.result;throw Error('新建已提交或结果未知，请刷新会话列表，勿重复新建')}this.ledger[id]={state:'sending'};this.save();try{await this.connect();let result=await this.rpc('session.create',this.nativeAuth?{source:'gui',request_id:b.requestId,title:b.title,cwd:b.cwd}:{source:'desktop',title:b.title,cwd:b.cwd,close_on_disconnect:false});if(this.nativeAuth){if(!result.session_id)throw Error('Hermes 未返回新会话编号');result={...result,session_key:result.session_id}};this.ledger[id]={state:'done',result};this.save();return result}catch(e){this.ledger[id]={state:'unknown'};this.save();throw e}}
 async createTest(){await this.connect();if(this.nativeAuth)throw Error('新版 Hermes 请使用专用会话手动测试，禁止自动创建真实任务');const r=await this.rpc('session.create',{source:'desktop',title:'G-Collie · Hermes 手机控制测试',cwd:join(this.root,'test-workspace'),close_on_disconnect:false});return r}
 async manage(key:string,b:any){if(!/^[a-zA-Z0-9_-]+$/.test(key))throw Error('无效 Hermes 会话 ID');const patch=hermesManagePatch(b);if(this.busy.has(key))throw Error('此会话有操作正在提交');this.busy.add(key);try{await this.connect();const res=await fetch(this.origin+'/api/sessions/'+encodeURIComponent(key),{method:'PATCH',headers:{...(this.nativeAuth?{'x-hermes-gateway-ticket':await hermesGatewayTicket(this.origin,'native-http')}:{Authorization:`Bearer ${this.token}`}), 'Content-Type':'application/json'},body:JSON.stringify(patch),signal:AbortSignal.timeout(8000)});const data:any=await res.json().catch(()=>null);if(!res.ok)throw Error(res.status===404?'这个会话还没有写入历史记录，先发一条消息再操作':data?.detail||data?.error||('修改失败（'+res.status+'）'));this.notify();return data??{ok:true}}finally{this.busy.delete(key)}}
 private async answerGatewayRequest(raw:any,b:any,sessionId:string){
  const request=raw.open_requests?.find((r:any)=>r.id===b.pendingId);
  if(!request||!String(request.id).startsWith('srq-'))throw Error('请求已过期，请刷新');
  const frame=hermesAnswer(raw,b);
  if(this.socket?.readyState!==WebSocket.OPEN)throw Error('Hermes 已断开，回答结果未知');
  // A server request takes a JSON-RPC response, never a prompt/RPC method. No value is persisted.
  this.socket.send(JSON.stringify({jsonrpc:'2.0',...frame}));
  for(let attempt=0;attempt<5;attempt++){
   const check=await this.rpc('session.events.since',{session_id:sessionId,last_sequence:0,...raw.replay_epoch?{replay_epoch:raw.replay_epoch}:{}});
   if(check.replay_epoch!==raw.replay_epoch)throw Error('Hermes 连接已变化，回答结果未知，请刷新核对');
   if(Array.isArray(check.open_requests)&&!check.open_requests.some((r:any)=>r.id===b.pendingId))return{status:'resolved',requestId:b.pendingId};
   await new Promise(resolve=>setTimeout(resolve,40));
  }
  throw Error('Hermes 回答结果未知，请刷新核对；不会重复提交');
 }
 async action(key:string,b:any){
  if(typeof b.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(b.requestId))throw Error('无效操作编号');
  const id=key+':'+b.requestId,old=this.ledger[id];if(old){if(old.state==='done')return old.result;throw Error('操作已提交或结果未知，不重复执行')}
  if(this.busy.has(key))throw Error('此会话有操作正在提交');this.busy.add(key);
  try{
   await this.connect();const{row,raw}=await this.snapshot(key,true);let method='',params:any,media:any[]=[],serverRequest=false,privateRequest:string|undefined;
   if(b.action==='send'){
    const prepared=await prepareAgentMedia(b.text,b.attachments||[]);media=prepared.files.filter(f=>f.image);if(media.length>10)throw Error('每次最多发送 10 张图片');
    const input=attachmentInput(prepared.text,prepared.files,64000);method='prompt.submit';params={session_id:row.id,text:input.filter(i=>i.type==='text').map(i=>i.text).join('\n')||'请查看附加的图片',...(this.nativeAuth?{submission_id:b.requestId}:{})};
   }else if(b.action==='stop'){
    if(!raw.running||String(raw.turn_started_at)!==b.turnId)throw Error('执行轮次已变化，请刷新');method='session.interrupt';params={session_id:row.id,...(this.nativeAuth?{execution_generation:raw.execution_generation}:{})};
   }else if(b.action==='answer'){
    if(this.nativeAuth){
     if(!Number.isSafeInteger(b.expectedGeneration)||b.expectedGeneration!==raw.execution_generation)throw Error('请求轮次已变化，请刷新后回答');
     if(typeof b.requestEpoch!=='string'||!b.requestEpoch||b.requestEpoch!==raw.replay_epoch)throw Error('请求连接已变化，请刷新后回答');
     if(raw.prompts?.some((p:any)=>p.prompt_id===b.pendingId)){const answer=hermesGatewayAnswer(raw,b,row.id);method=answer.method;params=answer.params}
     else{hermesAnswer(raw,b);serverRequest=true;privateRequest=JSON.stringify([key,b.pendingId,raw.execution_generation,raw.replay_epoch]);if(Object.values(this.ledger).some(record=>record.privateRequest===privateRequest&&['sending','unknown'].includes(record.state)))throw Error('此安全输入的回答结果未知，请刷新核对；不会重复提交')}
    }else{method='request.answer';params=hermesAnswer(raw,b)}
   }else throw Error('未知操作');
   this.ledger[id]={state:'sending',...(privateRequest?{privateRequest}:{})};this.save();
   try{
    const staged:any[]=[];
    for(const file of media){const uploaded=await this.rpc('image.attach_bytes',{session_id:row.id,filename:file.name,content_base64:(await readFile(file.path)).toString('base64')});if(this.nativeAuth){if(uploaded?.attached!==true||typeof uploaded.path!=='string'||!uploaded.path.startsWith('/')||!['image/png','image/jpeg','image/gif','image/webp'].includes(uploaded.mime))throw Error('Hermes 图片暂存回执无效，发送结果未知');staged.push({path:uploaded.path,mime:uploaded.mime})}}
    if(this.nativeAuth&&staged.length)params.attachments=staged;
    const result=serverRequest?await this.answerGatewayRequest(raw,b,row.id):await this.rpc(method,params);
    if(result?.status==='expired'||result?.status==='already_resolved')throw Error('请求已过期，请刷新核对');
    this.ledger[id]={state:'done',result,...(privateRequest?{privateRequest}:{})};this.save();this.notify();return result;
   }catch(e){this.ledger[id]={state:'unknown',...(privateRequest?{privateRequest}:{})};this.save();throw e}
  }finally{this.busy.delete(key)}
 }

 close(){this.closed=true;this.socket?.close()}
}
