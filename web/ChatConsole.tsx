import ProcessRecord from './ProcessRecord';
import ServerSettings from './ServerSettings';
import RequestInput from './RequestInput';
import {SchedulesPage,DownloadsPage,DiagnosticsPage} from './WorkspacePages';
import Projects from './Projects';
import CollieBrand from'./CollieBrand';
import UsageDashboard from'./UsageDashboard';
import SessionFilters from'./SessionFilters';
import AttachmentPicker,{AttachmentPreviews,type Upload}from'./AttachmentPicker';
import WorkspaceSettings from './WorkspaceSettings';
import React,{useEffect,useRef,useState} from 'react';
import{ArrowLeft,Info,Wrench,Clock,Download,Menu,SquarePen,Search,Folder,MessageCircle,ChevronRight,ChevronDown,Plus,ArrowUp,RefreshCw,X,PanelLeft,MoreHorizontal,Copy,Check,Activity,SlidersHorizontal,Monitor,ArrowDown,Terminal,Archive}from'lucide-react';
import SessionMedia from './SessionMedia';import AgentIcon from'./AgentIcon';import SessionMenu from'./SessionMenu';
type Session={managed?:boolean;id:string;agent:string;title:string;cwd:string;project:string;projectPath?:string;model?:string;updatedAt:number;archived:boolean;usage:any};
const agentPrefixes:Record<string,string>={'Claude Code':'claude',Hermes:'hermes',Codex:'codex'};
function matchesDraftAgent(id:unknown,agent:string):id is string{
 const prefix=agentPrefixes[agent];
 if(!prefix||typeof id!=='string'||!id.startsWith(prefix+':'))return false;
 return id.slice(prefix.length+1).trim().length>0;
}
type FirstSendState =
 | {phase:'idle'|'submitting'|'confirming'}
 | {phase:'failed';reason:string;invalidImage?:string};
type CreateFailure = {message?:string;code?:string;attachmentId?:string;outcome?:string;status?:number};

function displayCreateFailure(message?:string){
 if(typeof message!=='string'||!message.trim())return '请检查电脑连接后重试。';
 // Older servers may return converter commands, local paths or filesystem diagnostics.
 if(message.length>300||/[\r\n]|Command failed|ffmpeg|(?:ENOENT|EACCES|ENOTDIR|EPERM):|(?:^|[\s"'：:])(?:\/|[A-Za-z]:[\\/])\S+/i.test(message)){
  return '电脑处理首条消息失败，请检查项目和附件后重试。';
 }
 return message;
}
function FirstSendNotice({state,hasAttachments,imageRemoved}:{state:FirstSendState;hasAttachments:boolean;imageRemoved:boolean}){
 if(state.phase==='idle')return null;
 const failed=state.phase==='failed';
 const title=failed?'首条消息未发送':state.phase==='confirming'?'正在确认发送结果':'正在发送首条消息…';
 const note=failed?(imageRemoved?'可编辑草稿后重新发送。':state.reason):state.phase==='confirming'?
  `${hasAttachments?'正文和附件':'草稿'}已保留，可刷新会话查询回执。`:'';
 return <section className={'first-send-notice'+(failed?' failed':'')} role={failed?'alert':'status'}>
  {failed?<Info aria-hidden="true"/>:state.phase==='confirming'?<Clock aria-hidden="true"/>:<RefreshCw aria-hidden="true"/>}
  <div><strong>{title}</strong>{note&&<p>{note}</p>}</div>
 </section>;
}
export default function ChatConsole({api,onDisconnect,role}:{role:string;onDisconnect:()=>void;api:(p:string,body?:any)=>Promise<any>}){
const[data,setData]=useState<{sessions:Session[];projects:any[];warnings:string[]}>({sessions:[],projects:[],warnings:[]}),[detail,setDetail]=useState<any>(null),[drawer,setDrawer]=useState(false),[query,setQuery]=useState(''),[agent,setAgent]=useState('all'),[project,setProject]=useState(''),[page,setPage]=useState('chat'),[error,setError]=useState(''),[loading,setLoading]=useState(false),[online,setOnline]=useState(false),[info,setInfo]=useState(false),[filter,setFilter]=useState(false),[copied,setCopied]=useState(''),[sending,setSending]=useState(false),[answers,setAnswers]=useState<Record<string,string>>({});
// Keep unsent text with its session while navigating in this tab.
const [drafts,setDrafts]=useState<Record<string,string>>({});
const sessionId=detail?.id as string|undefined;
const draft=sessionId?drafts[sessionId]||'':'';
function setDraft(value:string|((previous:string)=>string)){
 if(!sessionId)return;
 setDrafts(previous=>{
  const next={...previous};
  const text=typeof value==='function'?value(previous[sessionId]||''):value;
  if(text)next[sessionId]=text;else delete next[sessionId];
  return next;
 });
}
const firstSend=useRef<string|null>(null);
const currentRole=useRef(role);
currentRole.current=role;
const [firstSendState,setFirstSendState]=useState<FirstSendState>({phase:'idle'});
function resetFirstSend(){firstSend.current=null;setFirstSendState({phase:'idle'})}
function leaveDraft(){
 if(!detail?.draft)return;
 resetFirstSend();setDraft('');setError('');
}
const[connectingSession,setConnectingSession]=useState(false);const[sidebarCollapsed,setSidebarCollapsed]=useState(false);
const[uploads,setUploads]=useState<Upload[]>([]),[uploading,setUploading]=useState(false);useEffect(()=>{setUploads([]);setUploading(false)},[detail?.id]);
const[shareOpen,setShareOpen]=useState(false),[shareResult,setShareResult]=useState<any>(null);
const[homeAgent,setHomeAgent]=useState('Codex');const[showJump,setShowJump]=useState(false);const[more,setMore]=useState(false);
const[agentMenu,setAgentMenu]=useState(false);
const[deleteDialog,setDeleteDialog]=useState<any>(null),[deleting,setDeleting]=useState(false);const deleteGate=useRef(false);
async function showDelete(){const target=detail;if(!target||target.draft)return;setDeleteDialog({target,checking:true});if(role==='view'||!online){setDeleteDialog({target,checking:false,eligibility:{allowed:false,reason:role==='view'?'当前连接只读，无法删除会话。':'电脑离线，请恢复连接后删除。'}});return}try{const eligibility=await api('/local/'+encodeURIComponent(target.id)+'/delete-eligibility');setDeleteDialog((current:any)=>current?.target.id===target.id?{...current,checking:false,eligibility}:current)}catch(e){setDeleteDialog((current:any)=>current?.target.id===target.id?{...current,checking:false,error:'无法检查删除条件，请恢复连接后重新检查。',eligibility:{allowed:false}}:current)}}
async function deleteCurrent(){const dialog=deleteDialog;if(!dialog||deleteGate.current||dialog.unknown||!dialog.eligibility?.allowed||!online||role==='view'||sending||loading||connectingSession||dialog.target.draft||['running','starting','waiting'].includes(dialog.target.status))return;deleteGate.current=true;setDeleting(true);setDeleteDialog((d:any)=>({...d,error:''}));try{const result=await api('/local/'+encodeURIComponent(dialog.target.id)+'/delete',{requestId:requestId()});if(result?.ok!==true||result?.deleted!==true)throw Object.assign(Error('删除返回结果无效，无法确认删除结果'),{outcome:'unknown',code:'delete_result_unknown'});const deletedIds=new Set<string>([dialog.target.id,...(Array.isArray(result.deletedIds)?result.deletedIds.filter((id:unknown):id is string=>typeof id==='string'):[])]);generation.current++;for(const id of deletedIds){olderHistory.current.delete(id);historyCursors.current.delete(id)}setData(current=>({...current,sessions:current.sessions.filter(s=>!deletedIds.has(s.id))}));if(deletedIds.has(detail?.id))home();setDeleteDialog(null);setError('会话已删除');}catch(e){const failure=e as Error&{outcome?:string;code?:string;status?:number};const unknown=failure.outcome==='unknown'||(!failure.outcome&&!failure.status)||/结果未知|无法确认/.test(failure.message);setDeleteDialog((d:any)=>({...d,unknown,eligibility:{allowed:false},needsRecheck:!unknown,error:unknown?'删除结果尚未确认，请刷新列表核对；不会自动再次删除。':failure.message}))}finally{deleteGate.current=false;setDeleting(false)}}
async function checkDeletedResult(){if(!deleteDialog||deleting)return;setDeleting(true);try{const result=await api('/local');setData(result);setOnline(true);if(!result.sessions.some((s:any)=>s.id===deleteDialog.target.id)){if(detail?.id===deleteDialog.target.id)home();setDeleteDialog(null);setError('列表中已无此会话，请以来源电脑的记录为准。')}else setDeleteDialog((d:any)=>({...d,error:'列表中仍有此会话，删除结果未确认。请在来源电脑核对，暂不重复删除。'}))}catch{setDeleteDialog((d:any)=>({...d,error:'刷新失败，删除结果未确认；原会话保留显示。'}))}finally{setDeleting(false)}}

const[newChat,setNewChat]=useState(false),[newAgent,setNewAgent]=useState('Hermes'),[newCwd,setNewCwd]=useState('');
function beginNew(){const paths=data.projects.map((p:any)=>p.path);const pref=detail?.cwd||project||'';setNewAgent(detail?.agent||homeAgent);setNewCwd(paths.includes(pref)?pref:'');setNewChat(true);setDrawer(false);setInfo(false)}
function createSession(){if(sending)return;generation.current++;leaveDraft();const id='draft:'+requestId();setDetail({id,draft:true,agent:newAgent,title:'新会话',cwd:newCwd,events:[],status:'idle',readOnly:false});setError('');setPage('chat');setNewChat(false);setLoading(false);setConnectingSession(false);localStorage.removeItem('orbit-session');requestAnimationFrame(()=>composerRef.current?.focus())}
async function renameSession(id:string,title:string){await api('/hermes/'+encodeURIComponent(id),{action:'rename',title,requestId:requestId()});await load();if(detail?.id===id)setDetail(await api('/local/'+encodeURIComponent(id)))}
async function archiveSession(id:string){await api('/hermes/'+encodeURIComponent(id),{action:'archive',requestId:requestId()});await load();if(detail?.id===id)home()}
const scroller=useRef<HTMLDivElement>(null),generation=useRef(0),mounted=useRef(true),restore=useRef(false),focusRef=useRef<HTMLButtonElement>(null),searchRef=useRef<HTMLInputElement>(null),drawerRef=useRef<HTMLElement>(null),composerRef=useRef<HTMLTextAreaElement>(null);
const olderHistory=useRef(new Map<string,any[]>()),historyCursors=useRef(new Map<string,string|null>()),historyLoading=useRef(false);
function mergeHistory(d:any){if(!historyCursors.current.has(d.id))historyCursors.current.set(d.id,d.historyCursor||null);const rows=new Map<string,any>();for(const e of [...olderHistory.current.get(d.id)||[],...d.events||[]])rows.set(String(e.id),e);olderHistory.current.set(d.id,[...rows.values()]);return{...d,events:[...rows.values()]}}
async function loadOlderHistory(){const d=detail,el=scroller.current;if(!d||!el||historyLoading.current||!online)return;const cursor=historyCursors.current.get(d.id);if(!cursor)return;historyLoading.current=true;const g=generation.current,oldHeight=el.scrollHeight,offset=el.scrollTop;try{const p=await api('/local/'+encodeURIComponent(d.id)+'/history?before='+encodeURIComponent(cursor));if(g!==generation.current||!mounted.current)return;olderHistory.current.set(d.id,[...p.events,...olderHistory.current.get(d.id)||[]]);historyCursors.current.set(d.id,p.historyCursor||null);setDetail((current:any)=>current?.id===d.id?mergeHistory(current):current);requestAnimationFrame(()=>{if(g===generation.current&&scroller.current)scroller.current.scrollTop=offset+scroller.current.scrollHeight-oldHeight})}catch(e){setError((e as Error).message)}finally{historyLoading.current=false}}
const listError=useRef('');
async function load(){
 try{
  const data=await api('/local');
  if(!mounted.current)return;
  setData(data);setOnline(true);
  const previous=listError.current;listError.current='';
  if(previous)setError(current=>current===previous?'':current);
 }catch(e){
  if(!mounted.current)return;
  listError.current=(e as Error).message;
  setOnline(false);setError(listError.current);
 }
}
async function open(id:string,created=false){const g=++generation.current;
 if(detail?.draft&&id!==detail.id){
  leaveDraft();
  setDetail(created?{...detail,id,draft:false,readOnly:true,status:'unknown'}:null);
  if(created)localStorage.setItem('orbit-session',id);
 }
setLoading(true);setConnectingSession(false);setDrawer(false);setPage('chat');setError('');setInfo(false);try{let d=await api('/local/'+encodeURIComponent(id));if(g!==generation.current||!mounted.current)return;setDetail(mergeHistory(d));id=d.id;localStorage.setItem('orbit-session',id);setOnline(true);if(currentRole.current!=='view'&&!d.managed&&!d.desktopLive&&!d.archived){setConnectingSession(true);try{d=await api('/local/'+encodeURIComponent(id)+'/activate',{});if(g!==generation.current||!mounted.current)return;setDetail(mergeHistory(d));localStorage.setItem('orbit-session',d.id)}catch(e){if(g===generation.current)setDetail((current:any)=>current?.id===id?{...current,connectionState:'failed',desktopError:(e as Error).message}:current)}}}catch(e){if(g===generation.current)setError((e as Error).message)}finally{if(g===generation.current){setLoading(false);setConnectingSession(false)}}}

function home(){generation.current++;leaveDraft();setLoading(false);setConnectingSession(false);setDetail(null);setPage('chat');setDrawer(false);setInfo(false);localStorage.removeItem('orbit-session')}
useEffect(()=>{mounted.current=true;load();if(!restore.current){restore.current=true;const id=localStorage.getItem('orbit-session');if(id)open(id)}const t=setInterval(()=>{if(!document.hidden)void load()},15000);return()=>{mounted.current=false;clearInterval(t)}},[]);
useEffect(()=>{if(detail)requestAnimationFrame(()=>{if(scroller.current)scroller.current.scrollTop=scroller.current.scrollHeight})},[detail?.id]);
useEffect(()=>{const el=composerRef.current;if(!el)return;el.style.height='auto';el.style.height=Math.min(el.scrollHeight,160)+'px'},[draft,detail?.id]);
useEffect(()=>{document.body.style.overflow=drawer?'hidden':'';if(drawer)drawerRef.current?.querySelector<HTMLButtonElement>('button')?.focus({preventScroll:true});return()=>{document.body.style.overflow=''}},[drawer]);
useEffect(()=>{function key(e:KeyboardEvent){if(e.key==='Escape'){setDrawer(false);setInfo(false);setAgentMenu(false);focusRef.current?.focus()}if(drawer&&e.key==='Tab'){const els=drawerRef.current?.querySelectorAll<HTMLElement>('button,input,select');if(!els?.length)return;const first=els[0],last=els[els.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}}document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[drawer]);
const requestId=()=>Array.from(crypto.getRandomValues(new Uint8Array(16)),v=>v.toString(16).padStart(2,'0')).join('');
const isCurrent=(token:number)=>mounted.current&&generation.current===token;
function markFirstSendFailed(failure:CreateFailure){
 firstSend.current=null;
 const invalidImage=failure.code==='session_create_invalid_image'&&uploads.some(file=>file.id===failure.attachmentId&&file.image)
  ?failure.attachmentId:undefined;
 const reason=failure.code==='session_create_invalid_image'?
  (invalidImage?'图片无法读取，请移除或更换。':'电脑读取图片失败，可检查附件后重试。'):
  displayCreateFailure(failure.message);
 setFirstSendState({phase:'failed',reason,invalidImage});
}
async function checkFirstReceipt(){
 const id=firstSend.current;
 if(!id||firstSendState.phase!=='confirming')return;
 const token=generation.current;
 try{
  const receipt=await api('/sessions/requests/'+encodeURIComponent(id.slice(6)));
  if(!isCurrent(token)||firstSend.current!==id)return;
  if(receipt?.state==='done'&&matchesDraftAgent(receipt.result?.id,detail.agent)){
   void open(receipt.result.id,true);
   void load();
  }else if(receipt?.state==='failed'){
   markFirstSendFailed({message:receipt.error,code:receipt.code,attachmentId:receipt.attachmentId});
  }
 }catch{/* An interrupted receipt read leaves the draft locked. */}
}
useEffect(()=>{
 if(firstSendState.phase!=='confirming'||page!=='chat')return;
 let active=true,timer:ReturnType<typeof setTimeout>,delay=1000;
 async function poll(){
  if(!document.hidden)await checkFirstReceipt();
  if(active){timer=setTimeout(poll,delay);delay=Math.min(15000,delay*2)}
 }
 void poll();
 return()=>{active=false;clearTimeout(timer)};
},[firstSendState.phase,detail?.id,page]);
async function submitDraft(){
 const id=detail.id;
 if(firstSend.current||!controllable||uploading||invalidImagePresent)return;
 const token=generation.current;
 firstSend.current=id;
 setFirstSendState({phase:'submitting'});setError('');
 try{
  const result=await api('/sessions',{agent:detail.agent,cwd:detail.cwd,prompt:draft,attachments:uploads.map(file=>file.id),draftId:id,requestId:id.slice(6)});
  if(!isCurrent(token)||firstSend.current!==id)return;
  if(!matchesDraftAgent(result?.id,detail.agent))throw Error('新建已提交或结果未知，请刷新列表确认，勿重复发送');
  void open(result.id,true);
  void load();
 }catch(e){
  if(!isCurrent(token)||firstSend.current!==id)return;
  const failure=e as CreateFailure;
  if(failure.outcome==='failed'||failure.status===401||failure.status===403){
   markFirstSendFailed(failure);
  }else{
   setFirstSendState({phase:'confirming'});
  }
 }
}
async function control(action:string,extra:any={}){
 if(sending)return;
 if(detail?.draft&&action==='send'){await submitDraft();return}
 const token=generation.current;
 setSending(true);setError('');
 try{
  const endpoint=detail?.desktopLive&&!detail?.managed&&action!=='create'?(detail.claudeLive?'/claude/':detail.hermesLive?'/hermes/':'/desktop/')+detail.nativeId:'/control/'+(action==='create'?'new':encodeURIComponent(detail.id));
  const result=await api(endpoint,{action,requestId:requestId(),...extra});
  if(action==='send')setDraft('');
  if(!isCurrent(token))return;
  if(action==='create'){void open(result.id);void load();return}
  if(action==='answer')setAnswers({});
  if(action==='send')setUploads([]);
  const current=await api('/local/'+encodeURIComponent(detail.id));
  if(isCurrent(token))setDetail(mergeHistory(current));
 }catch(e){if(isCurrent(token))setError((e as Error).message)}
 finally{if(mounted.current)setSending(false)}
}
useEffect(()=>{if(!detail?.id||detail.draft||connectingSession||deleteDialog)return;if(detail.draft)return;const id=detail.id;let active=true;const t=setInterval(async()=>{if(document.hidden)return;try{const d=await api('/local/'+encodeURIComponent(id));if(active){setDetail((current:any)=>current?.id===id&&current.connectionState==='failed'&&!d.desktopLive?{...mergeHistory(d),connectionState:'failed',desktopError:current.desktopError}:mergeHistory(d));setOnline(true)}}catch{if(active){setOnline(false);setDetail((current:any)=>current?.id===id?{...current,desktopLive:false,status:'unknown',readOnly:true}:current)}}},1000);return()=>{active=false;clearInterval(t)}},[detail?.id,connectingSession,!!deleteDialog]);
const controllable=role!=='view'&&online&&!loading&&!connectingSession&&!detail?.archived&&(detail?.draft||(detail?.managed&&!detail?.readOnly)||(detail?.desktopLive&&detail?.desktopControl));const activeTurn=controllable&&['running','starting','waiting'].includes(detail?.status);const canAppend=activeTurn&&detail?.desktopLive&&((detail?.agent==='Codex'&&['running','waiting'].includes(detail?.status))||(detail?.agent==='Hermes'&&detail?.status==='running'));const showFirstSend=detail?.draft&&firstSendState.phase!=='idle';
const draftLocked=detail?.draft&&['submitting','confirming'].includes(firstSendState.phase);
const invalidImagePresent=firstSendState.phase==='failed'&&!!firstSendState.invalidImage&&uploads.some(file=>file.id===firstSendState.invalidImage);
const composerBlocked=draftLocked||(activeTurn&&!canAppend);

const sessions=data.sessions.filter(s=>(agent==='all'||s.agent===agent)&&(!project||s.projectPath===project)&&`${s.title} ${s.cwd} ${s.model||''}`.toLowerCase().includes(query.toLowerCase()));
const dateGroup=(s:Session)=>{const start=new Date();start.setHours(0,0,0,0);const days=Math.floor((start.getTime()-s.updatedAt)/86400000);return days<1?'今天':days<2?'昨天':days<7?'过去 7 天':days<30?'过去 30 天':'更早'};
const groups=[...new Set(sessions.map(dateGroup))];const fmt=(n:any)=>typeof n==='number'?n.toLocaleString():'未知';
async function copy(id:string,text:string){try{await navigator.clipboard.writeText(text);setCopied(id);setTimeout(()=>setCopied(''),1500)}catch{setError('当前浏览器无法自动复制，请长按文字选择复制')}}
const attachmentPreviews=<AttachmentPreviews compact={showFirstSend} locked={draftLocked} disabled={!controllable||uploading||sending||draftLocked} files={uploads} onRemove={id=>setUploads(files=>files.filter(f=>f.id!==id))}/>;
const pageNavigation=<button ref={focusRef} className="icon-button aux-page-menu" aria-label="打开会话列表" aria-controls="session-navigation" aria-expanded={drawer} onClick={()=>{setDrawer(true);setSidebarCollapsed(false)}}><Menu size={20}/></button>;
const nav=(id:string)=>{generation.current++;setLoading(false);setConnectingSession(false);if(detail?.draft){leaveDraft();setDetail(null)}setPage(id);setDrawer(false);setInfo(false)};
return <div className={'chat-app '+(sidebarCollapsed?'sidebar-collapsed':'')}><div className={'chat-scrim '+(drawer?'visible':'')} onClick={()=>setDrawer(false)} aria-hidden="true"/>
<aside id="session-navigation" ref={drawerRef} className={'chat-sidebar '+(drawer?'is-open':'')} aria-label="会话导航"><div className="sidebar-top"><button className="icon-button" aria-label="收起侧边栏" onClick={()=>{setDrawer(false);setSidebarCollapsed(true)}}><PanelLeft size={22}/></button><span className="sidebar-brand"><CollieBrand/><span>G-Collie</span></span></div><button className="sidebar-device-picker" aria-label="电脑与连接" onClick={()=>nav('connection')}><Monitor size={16}/><span>我的工作电脑</span><i className={online?'online-dot':'online-dot offline'}/><ChevronRight size={13}/></button><div className="chat-search"><Search size={18}/><input ref={searchRef} placeholder="搜索会话" aria-label="搜索会话" value={query} onChange={e=>setQuery(e.target.value)}/>{query&&<button className="icon-button" aria-label="清空搜索" onClick={()=>setQuery('')}><X size={15}/></button>}</div><nav className="sidebar-actions"><button className={page==='chat'&&!detail?'selected':''} onClick={home}><MessageCircle size={19}/>会话首页</button><button className={page==='projects'?'selected':''} onClick={()=>nav('projects')}><Folder size={19}/>项目管理<span>{data.projects.length}</span></button><button className={page==='usage'?'selected':''} onClick={()=>nav('usage')}><Activity size={19}/>用量统计</button><button className={page==='schedules'?'selected':''} onClick={()=>nav('schedules')}><Clock size={19}/>定时任务</button><button className={page==='downloads'?'selected':''} onClick={()=>nav('downloads')}><Download size={19}/>下载内容</button></nav>{role==='owner'&&<nav className="sidebar-server"><span>电脑服务</span><button className={page==='connection'?'selected':''} onClick={()=>nav('connection')}><Monitor size={18}/>服务端管理</button></nav>}<div className="history-heading"><span>会话</span><button className="icon-button" aria-label="筛选会话" aria-expanded={filter} data-active={agent!=='all'||!!project} onClick={()=>{(document.activeElement as HTMLElement)?.blur();setFilter(!filter)}}><SlidersHorizontal size={16}/></button></div>{filter&&<SessionFilters agent={agent} project={project} projects={data.projects} sessions={data.sessions} onAgent={setAgent} onProject={setProject} onClose={()=>setFilter(false)}/>}{(agent!=='all'||project)&&<div className="active-session-filters"><button onClick={()=>setFilter(true)}>{agent==='all'?'全部助手':agent}{project?' · '+(data.projects.find(p=>p.path===project)?.name||'所选项目'):''}<ChevronRight size={13}/></button><button aria-label="清除筛选" onClick={()=>{setAgent('all');setProject('')}}><X size={14}/></button></div>}<div className="chat-history">{groups.map(group=><section key={group}><h3>{group}</h3>{sessions.filter(s=>dateGroup(s)===group).map(s=><button className={'history-link '+(detail?.id===s.id?'selected':'')} key={s.id} title={s.title} onClick={()=>open(s.id)}><AgentIcon agent={s.agent}/><span>{s.managed?'[独立测试] ':''}{s.title}</span>{s.archived&&<Archive size={13}/>}</button>)}</section>)}{!sessions.length&&<p className="muted empty-search">{data.sessions.length?'没有匹配的会话':'正在读取本机会话…'}</p>}</div><WorkspaceSettings api={api} role={role} online={online} onConnection={()=>nav('connection')} onDisconnect={onDisconnect} onDiagnostics={()=>nav('diagnostics')}/></aside>
<main className={'chat-main '+(detail&&page==='chat'?'compact-conversation ':'')+(info&&detail&&page==='chat'?'with-context':'')}><header className="desktop-topbar"><button className="icon-button desktop-sidebar-toggle" aria-label="打开会话列表" onClick={()=>{setDrawer(true);setSidebarCollapsed(false)}}><PanelLeft size={19}/></button><button className="desktop-computer" onClick={()=>nav('connection')}><Monitor size={17}/><span>我的工作电脑</span><ChevronRight size={13}/></button><span className="desktop-connection"><i className={online?'online-dot':'online-dot offline'}/>{online?'已连接':'连接中断'}</span><div className="header-right"><button className="desktop-new" disabled={role==='view'} onClick={beginNew}><SquarePen size={16}/>新建会话</button><button className="icon-button" aria-label="更多操作" aria-expanded={more} onClick={()=>setMore(!more)}><MoreHorizontal size={19}/></button></div>{more&&<><button className="desktop-menu-backdrop" aria-label="关闭更多操作" onClick={()=>setMore(false)}/><div className="desktop-more" role="menu">{[['connection',role==='owner'?'服务端管理':'电脑与连接'],['diagnostics','故障诊断'],['usage','用量统计']].map(([id,label])=><button key={id} role="menuitem" onClick={()=>{setMore(false);nav(id)}}>{label}<ChevronRight size={15}/></button>)}</div></>}</header><header className={'chat-header '+(!detail||page!=='chat'?'home-header':'')}>{page!=='chat'?<button className="icon-button page-home-back" aria-label="返回会话首页" title="返回会话首页" onClick={home}><ArrowLeft size={23}/></button>:<button ref={focusRef} className="icon-button menu-toggle" aria-label="打开会话列表" aria-expanded={drawer} onClick={()=>{setDrawer(true);setSidebarCollapsed(false)}}><Menu size={23}/></button>}{detail&&page==='chat'?<div className="desktop-session-heading">{detail.draft?<button className="chat-model" onClick={beginNew}><AgentIcon agent={detail.agent}/>{detail.agent}<ChevronDown size={16}/></button>:<SessionMenu agent={detail.agent} title={detail.title} cwd={detail.cwd} nativeId={detail.nativeId||detail.id} onShare={async()=>{setShareResult(null);setShareOpen(true);try{setShareResult(await api('/share/'+encodeURIComponent(detail.id)))}catch(e){setError((e as Error).message)}}} canManage={role!=='view'&&online&&detail.agent==='Hermes'&&!detail.managed} onInfo={()=>setInfo(true)} onRename={title=>renameSession(detail.nativeId||detail.id,title)} onArchive={()=>archiveSession(detail.nativeId||detail.id)} onError={message=>setError(message)} onDelete={()=>void showDelete()}/>}<span className="desktop-session-title" title={detail.title}>{detail.title}</span></div>:<span className="chat-model-title collie-header-title"><CollieBrand/><span>G-Collie</span></span>}<div className="header-right"><button className="icon-button" aria-label="故障诊断" title="故障诊断" onClick={()=>nav('diagnostics')}><Wrench size={19}/></button>{detail&&page==='chat'&&<button className="icon-button" aria-label="刷新会话" disabled={loading||(detail.draft&&firstSendState.phase!=='confirming')} onClick={()=>detail.draft?checkFirstReceipt():open(detail.id)}><RefreshCw size={19} className={loading?'spinning':''}/></button>}<button className="icon-button new-chat-trigger" title="新建会话" aria-label="新建会话" disabled={role==='view'} onClick={beginNew}><SquarePen size={22}/></button></div></header>
{error&&<div role="alert" className="chat-error">{error}{detail?.agent==='Codex'&&/额度|usage.limit|rate.limit|quota/i.test(error)&&<button className="outlined-button" onClick={()=>nav('usage')}>查看额度与重置卡</button>}<button className="icon-button" aria-label="关闭提示" onClick={()=>setError('')}><X size={16}/></button></div>}
{agentMenu&&<><div className="agent-menu-dismiss" onClick={()=>setAgentMenu(false)}/><section className="agent-switch-menu" aria-label="助手与会话"><p>查看会话</p>{['all','Codex','Hermes','Claude Code'].map(a=><button key={a} onClick={()=>{setAgent(a);setProject('');setQuery('');setFilter(true);setDrawer(true);setAgentMenu(false)}}>{a==='all'?<MessageCircle size={21}/>:<AgentIcon agent={a}/>}<span>{a==='all'?'全部助手':a}<small>{a==='all'?'浏览所有最近会话':`查看 ${a} 的会话记录`}</small></span>{agent===a&&<Check size={17}/>}</button>)}<button className="agent-menu-create" onClick={()=>{setAgentMenu(false);beginNew()}}><SquarePen size={20}/><span>新建会话</span><Plus size={17}/></button></section></>}
{shareOpen&&detail&&<div className="new-chat-overlay"><section className="new-chat-sheet" role="dialog" aria-modal="true" aria-label="分享会话"><div><strong>分享会话</strong><button className="icon-button" aria-label="关闭分享" disabled={sending} onClick={()=>setShareOpen(false)}><X size={18}/></button></div><p>创建 G-Collie 局域网只读快照，包含当前加载记录中的用户和助手文字，不包含工具记录。链接有效期 7 天，访问者需要能连接这台电脑。</p><p>持有链接的人可以查看快照内容。创建前请检查下面的内容。</p><details className="share-preview"><summary>预览分享内容 · {detail.title}</summary>{detail.events.filter((e:any)=>['user','assistant'].includes(e.role)).map((e:any)=><article key={e.id}><b>{e.role==='user'?'你':detail.agent}</b><p>{e.text}</p></article>)}</details>{shareResult?<><label>分享链接<input aria-label="分享链接" readOnly value={shareResult.url||shareResult.shareUrl||shareResult.link||''} onFocus={e=>e.target.select()}/></label><button className="outlined-button" onClick={()=>copy('share',shareResult.url||shareResult.shareUrl||shareResult.link||'')}>{copied==='share'?'已复制':'复制链接'}</button>{shareResult.kind==='orbit'?<button className="outlined-button" disabled={sending} onClick={async()=>{setSending(true);try{await api('/share/'+encodeURIComponent(detail.id),{action:'revoke',key:shareResult.key});setShareResult(null);setShareOpen(false)}catch(e){setError((e as Error).message)}finally{setSending(false)}}}>撤销此分享</button>:<p>这是 Codex 原生分享快照。</p>}</>:<button className="outlined-button" disabled={sending} onClick={async()=>{setSending(true);try{const r=await api('/share/'+encodeURIComponent(detail.id),{action:'create',requestId:requestId()});setShareResult(r)}catch(e){setError((e as Error).message);setShareOpen(false)}finally{setSending(false)}}}>{sending?'正在生成…':'创建分享链接'}</button>}</section></div>}
{deleteDialog&&<div className="new-chat-overlay"><section className="new-chat-sheet delete-session-sheet" role="dialog" aria-modal="true" aria-label="删除会话"><div><strong>删除会话</strong><button className="icon-button" aria-label="关闭删除会话" disabled={deleting} onClick={()=>setDeleteDialog(null)}><X size={18}/></button></div><p><strong>{deleteDialog.target.title}</strong><br/>我的工作电脑 · {deleteDialog.target.agent}</p><p>将删除电脑端原始会话及其压缩、重置历史，停止该会话的 G-Collie 提醒并撤销 G-Collie 分享，无法撤销。不删除项目文件；其他已加载页面可能需刷新。</p>{deleteDialog.checking&&<p role="status">正在检查删除条件…</p>}{!deleteDialog.checking&&deleteDialog.eligibility?.reason&&<p>{deleteDialog.eligibility.reason}</p>}{deleteDialog.error&&<p className="error" role="alert">{deleteDialog.error}</p>}<div className="delete-session-actions"><button className="outlined-button" autoFocus disabled={deleting} onClick={()=>setDeleteDialog(null)}>取消</button>{deleteDialog.unknown?<button className="outlined-button" disabled={deleting} onClick={checkDeletedResult}>{deleting?'正在刷新…':'刷新列表核对'}</button>:deleteDialog.needsRecheck?<button className="outlined-button" disabled={deleting} onClick={()=>void showDelete()}>重新检查删除条件</button>:<button className="outlined-button danger-action" disabled={deleting||deleteDialog.checking||!online||role==='view'||sending||loading||connectingSession||['running','starting','waiting'].includes(deleteDialog.target.status)||!deleteDialog.eligibility?.allowed} onClick={deleteCurrent}>{deleting?'正在删除…':deleteDialog.error?'重试删除':'确认删除'}</button>}</div></section></div>}
{newChat&&<div className="new-chat-overlay" onClick={()=>{if(!sending)setNewChat(false)}}><section className="new-chat-sheet" role="dialog" aria-modal="true" aria-label="新建会话" onClick={e=>e.stopPropagation()}><div><strong>新建会话</strong><button className="icon-button" aria-label="关闭新建会话" disabled={sending} onClick={()=>setNewChat(false)}><X size={18}/></button></div><p className="new-chat-subtitle">选择助手，开始一项新工作</p><div className="new-chat-agents" role="group" aria-label="选择助手">{['Codex','Hermes','Claude Code'].map(a=><button key={a} aria-pressed={newAgent===a} onClick={()=>setNewAgent(a)}><AgentIcon agent={a}/><span>{a}</span>{newAgent===a&&<Check size={17}/>}</button>)}</div><><p>工作在所选电脑的助手中执行。</p><label>项目 <select aria-label="新会话项目" value={newCwd} onChange={e=>setNewCwd(e.target.value)}><option value="">无项目 · 默认目录</option>{data.projects.map(p=><option key={p.path} value={p.path}>{p.name} · {p.path}</option>)}</select></label><p className="muted">先进入草稿，发送第一条消息时创建会话；名称自动生成。</p><button className="outlined-button" disabled={sending||role==='view'} onClick={createSession}>开始会话<ArrowUp size={18}/></button></></section></div>}
{info&&<section className="chat-info"><div><strong>{detail&&page==='chat'?detail.title:'G-Collie · 个人 Agent 控制台'}</strong><button className="icon-button" aria-label="关闭会话信息" onClick={()=>setInfo(false)}><X size={18}/></button></div><p>{detail&&page==='chat'?detail.cwd||'未关联项目':'连接电脑上的 Codex 与 Hermes 会话'}</p><p>{detail?.model||'本地只读接入'}{detail?.branch?' · '+detail.branch:''}</p><p>{detail?.managed?'独立测试后端 · '+detail.status:detail?.desktopLive?'桌面同一会话已连接 · '+({idle:'空闲',running:'执行中',waiting:'等待处理',unknown:'状态未知'} as Record<string,string>)[detail.status]:'桌面历史只读 · 未连接原执行后端'}</p>{['Codex','Hermes','Claude Code'].includes(detail?.agent)&&!detail?.managed&&<button className="outlined-button" disabled={role==='view'||sending||detail.archived} onClick={async()=>{setSending(true);try{const d=await api('/local/'+encodeURIComponent(detail.id)+'/activate',{});setDetail(mergeHistory(d));localStorage.setItem('orbit-session',d.id)}catch(e){setError((e as Error).message)}finally{setSending(false)}}}>{detail.archived?'已归档':detail.desktopLive?'重新连接桌面状态':'加载并连接会话'}</button>}{detail&&<p>输入 {fmt(detail.usage?.input)} · 输出 {fmt(detail.usage?.output)} · 缓存 {fmt(detail.usage?.cached)}</p>}</section>}
<div className="chat-scroll" ref={scroller} aria-busy={loading} onScroll={e=>{const el=e.currentTarget;setShowJump(el.scrollHeight-el.scrollTop-el.clientHeight>160);if(el.scrollTop<120)void loadOlderHistory()}}>
{page==='chat'?(detail?<div className="conversation">{!online&&<div className="conversation-note">{!online?'电脑连接中断 · 状态未知':detail.managed?'G-Collie 独立测试会话 · '+(({idle:'就绪',running:'执行中',starting:'提交中',waiting:'等待处理',completed:'已完成',interrupted:'已停止',failed:'失败',unknown:'状态未知'} as Record<string,string>)[detail.status]||detail.status):detail.desktopLive?'桌面实时连接 · '+({starting:'加载中',running:'执行中',waiting:'等待处理',idle:'空闲',unknown:'状态未知'} as Record<string,string>)[detail.status]:'桌面历史 · 运行状态未知'}</div>}{detail.agent==='Codex'&&/额度|usage.limit|rate.limit|quota/i.test(detail.error||detail.desktopError||'')&&<p role="status">Codex 额度受限。<button className="outlined-button" onClick={()=>nav('usage')}>查看额度与重置卡</button></p>}{detail.events.map((e:any)=>['tool','reasoning'].includes(e.role)?<ProcessRecord key={e.id} record={e} live={online&&['running','starting','waiting'].includes(detail.status)&&e.turnId===detail.turnId}>{e.role==='tool'&&Array.isArray(e.media)&&e.media.length>0&&<div className="message-content"><SessionMedia events={detail.events} session={detail.id} event={e} api={api}/></div>}</ProcessRecord>:<article className={'chat-message '+e.role} key={e.id}>{e.role==='assistant'&&<div className="message-agent"><AgentIcon agent={detail.agent}/><span>{detail.agent}</span></div>}<div className="message-content"><SessionMedia events={detail.events} session={detail.id} event={e} api={api}/></div>{e.role==='assistant'&&<div className="message-actions"><button className="icon-button" aria-label="复制回复" onClick={()=>copy(e.id,e.text)}>{copied===e.id?<Check size={16}/>:<Copy size={16}/>}</button></div>}</article>)}{!detail.events.length&&!showFirstSend&&<p className="muted">{detail.draft?'这是尚未创建的草稿，发送第一条消息开始。':'暂无可显示的历史'}</p>}{detail.liveInflight?.assistant&&<article className="chat-message assistant"><div className="message-agent"><AgentIcon agent={detail.agent}/>{detail.agent}</div><div className="message-content"><SessionMedia events={detail.events} session={detail.id} event={{text:detail.liveInflight.assistant}} api={api}/></div></article>}{connectingSession?<p className="muted" role="status">正在请求电脑加载历史会话…</p>:detail.desktopError&&<div className="history-connection"><p className="muted">{detail.desktopError}</p>{!detail.archived&&<button className="outlined-button" disabled={loading||sending} onClick={()=>open(detail.id)}>重新连接</button>}</div>}{detail.error&&<p role="alert" className="muted">{detail.error}</p>}{detail.pending&&<RequestInput key={detail.id+':'+detail.pending.id+':'+(detail.pending.generation??'legacy')+':'+(detail.pending.requestEpoch??'legacy')} pending={detail.pending} enabled={controllable} busy={sending} onAnswer={value=>control('answer',value)}/>}{!detail.draft&&<div className="conversation-end">已加载的会话记录</div>}</div>:<div className="chat-welcome"><div className="welcome-intro"><div className="welcome-companion"><CollieBrand hero/></div><h1>现在想继续哪项工作？</h1><p>帮你照看每一个 Agent</p></div><div className="welcome-shortcuts">{['Codex','Hermes','Claude Code'].map(a=><button key={a} aria-pressed={homeAgent===a} onClick={()=>setHomeAgent(a)}><AgentIcon agent={a}/><span>{a}</span></button>)}</div><section className="recent-conversations"><div className="recent-heading"><h2>{homeAgent} · 最近会话</h2><button className="home-new-session" disabled={role==='view'} onClick={beginNew}><SquarePen size={16}/>新建会话</button><button onClick={()=>{setAgent(homeAgent);setProject('');setQuery('');setDrawer(true);setSidebarCollapsed(false);searchRef.current?.focus()}}>查看全部会话<ChevronRight size={16}/></button></div>{data.sessions.filter(s=>s.agent===homeAgent&&!s.archived).sort((a,b)=>b.updatedAt-a.updatedAt).slice(0,4).map(s=><button key={s.id} onClick={()=>open(s.id)}><AgentIcon agent={s.agent}/><div><strong>{s.managed?'[独立测试] ':''}{s.title}</strong><small>{s.agent} · {s.project}</small></div><time>{new Date(s.updatedAt).toLocaleDateString('zh-CN',{month:'numeric',day:'numeric'})}</time><ChevronRight size={17}/></button>)}{!data.sessions.some(s=>s.agent===homeAgent&&!s.archived)&&<p className="muted">暂无 {homeAgent} 会话，点击新建会话开始工作。</p>}</section></div>):page==='projects'?<Projects navigation={pageNavigation} api={api} readOnly={role==='view'} projects={data.projects} onSelect={path=>{setSidebarCollapsed(false);setProject(path);setAgent('all');setQuery('');setFilter(true);setDrawer(true)}}/>:page==='schedules'?<SchedulesPage navigation={pageNavigation} api={api} sessions={data.sessions} readOnly={role==='view'}/>:page==='downloads'?<DownloadsPage navigation={pageNavigation} api={api} sessions={data.sessions}/>:page==='diagnostics'?<DiagnosticsPage navigation={pageNavigation} api={api} owner={role==='owner'}/>:page==='usage'?<UsageDashboard navigation={pageNavigation} api={api} onOpen={open} readOnly={role==='view'}/>:<ServerSettings navigation={pageNavigation} api={api} role={role} online={online} onDiagnostics={()=>nav('diagnostics')}/>}

</div>{page==='chat'&&detail&&<div className="chat-composer-wrap">{detail&&showJump&&<button className="scroll-bottom icon-button" aria-label="滚动到最新记录" onClick={()=>scroller.current?.scrollTo({top:scroller.current.scrollHeight,behavior:'smooth'})}><ArrowDown size={18}/></button>}{showFirstSend&&<FirstSendNotice state={firstSendState} hasAttachments={uploads.length>0} imageRemoved={firstSendState.phase==='failed'&&!!firstSendState.invalidImage&&!invalidImagePresent}/>}
{showFirstSend&&attachmentPreviews}<div className="chat-composer">{!showFirstSend&&attachmentPreviews}<textarea ref={composerRef} aria-label={controllable?"消息输入":"消息输入（只读）"} readOnly={draftLocked} disabled={!controllable||sending||(activeTurn&&!canAppend)} value={draft} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing&&controllable&&!sending&&!composerBlocked&&!invalidImagePresent&&!uploading&&(draft.trim()||uploads.length)){e.preventDefault();void control('send',{text:draft,attachments:uploads.map(f=>f.id)})}}} onChange={e=>{setDraft(e.target.value);e.target.style.height='auto';e.target.style.height=Math.min(e.target.scrollHeight,160)+'px'}} maxLength={4000} placeholder={connectingSession?'正在加载历史会话…':detail?.archived?'会话已归档，暂时只读':controllable?`向 ${detail.agent} 发送消息…`:detail?.desktopError?'暂未连接，可在上方重新连接':detail?'只读 · 暂不能发送消息':'选择会话查看进展'} rows={1}/><div><AttachmentPicker onInsert={text=>{if((draft+'\n'+text).length>4000){setError('草稿不能超过 4000 字');return}setDraft(current=>current+(current?'\n':'')+text)}} key={detail?.id||'none'} session={detail?.id||''} agent={detail?.agent||''} disabled={!controllable||sending||composerBlocked||!!detail?.managed} files={uploads} onChange={setUploads} onBusy={setUploading} onError={setError} api={api}/><span>{showFirstSend?'':controllable?(activeTurn?(detail.desktopLive?'桌面正在执行':'独立后端正在执行'):(detail.draft?'首条消息发送后创建会话':detail.desktopLive?'发送到电脑上的同一会话':'独立测试 · 只读沙箱')):"只读预览"}</span>{canAppend&&<button className="send-button" disabled={sending||uploading||(!draft.trim()&&!uploads.length)} aria-label="追加消息" onClick={()=>control('send',{text:draft,attachments:uploads.map(f=>f.id)})}><ArrowUp size={20}/></button>}{activeTurn?<button className="send-button" disabled={sending||!detail.turnId} aria-label="停止当前轮" onClick={()=>control('stop',{turnId:detail.turnId})}>■</button>:<button className="send-button" disabled={!controllable||composerBlocked||invalidImagePresent||sending||uploading||(!draft.trim()&&!uploads.length)} aria-label="发送消息" onClick={()=>control('send',{text:draft,attachments:uploads.map(f=>f.id)})}><ArrowUp size={20}/></button>}</div></div><p className="composer-disclaimer">工作在电脑执行 · Enter 发送，Shift + Enter 换行</p></div>}</main></div>
}
