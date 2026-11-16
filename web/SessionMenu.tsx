import React,{useEffect,useRef,useState} from 'react';
import AgentIcon from './AgentIcon';
import {Archive,ChevronDown,Copy,Info,Pencil,Share2,Trash2} from 'lucide-react';
type Props={
 agent:string;title:string;cwd?:string;nativeId:string;canManage:boolean;
 onShare:()=>void;
 onDelete:()=>void;
 onInfo:()=>void;
 onRename:(title:string)=>Promise<void>;
 onArchive:()=>Promise<void>;
 onError:(message:string)=>void;
};
export default function SessionMenu({agent,title,cwd,nativeId,canManage,onShare,onInfo,onRename,onArchive,onError,onDelete}:Props){
 const[open,setOpen]=useState(false),[mode,setMode]=useState<'menu'|'rename'|'archive'>('menu'),[draft,setDraft]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState('');
 const wrap=useRef<HTMLDivElement>(null);
 useEffect(()=>{
  if(!open)return;
  const away=(e:MouseEvent)=>{if(!wrap.current?.contains(e.target as Node))restart()};
  const esc=(e:KeyboardEvent)=>{if(e.key==='Escape')restart()};
  document.addEventListener('mousedown',away);document.addEventListener('keydown',esc);
  return()=>{document.removeEventListener('mousedown',away);document.removeEventListener('keydown',esc)};
 },[open]);
 useEffect(()=>restart(),[nativeId]);
 function restart(){setOpen(false);setMode('menu');setNote('');setDraft('')}
 async function copy(text:string,label:string){try{await navigator.clipboard.writeText(text);setNote(label+'已复制');setTimeout(()=>setNote(n=>n===label+'已复制'?'':n),1600)}catch{onError('当前浏览器无法自动复制，请长按文字选择复制')}}
 async function save(){const value=draft.trim();if(!value||busy)return;setBusy(true);try{await onRename(value);restart()}catch(e){onError((e as Error).message)}finally{setBusy(false)}}
 async function archive(){if(busy)return;setBusy(true);try{await onArchive();restart()}catch(e){onError((e as Error).message)}finally{setBusy(false)}}
 return <div className="session-menu" ref={wrap}>
  <button className="chat-model" aria-haspopup="menu" aria-expanded={open} aria-label="会话操作" title="会话操作" onClick={()=>{setOpen(!open);setMode('menu')}}><AgentIcon agent={agent}/>{agent}<ChevronDown size={16}/></button>
  {open&&<div className="session-menu-panel" role="menu" aria-label="会话操作">
   {mode==='rename'
    ?<div className="session-menu-form"><label>会话名称<input aria-label="新的会话名称" autoFocus maxLength={100} value={draft} onChange={e=>setDraft(e.target.value)} onKeyDown={e=>{if(e.key==='Enter')save()}}/></label><div className="session-menu-row"><button disabled={busy||!draft.trim()} onClick={save}>{busy?'保存中…':'保存'}</button><button disabled={busy} onClick={()=>setMode('menu')}>取消</button></div></div>
    :mode==='archive'
    ?<div className="session-menu-form"><p>归档后这个会话会从列表隐藏，需要在电脑上才能恢复。</p><div className="session-menu-row"><button disabled={busy} onClick={archive}>{busy?'归档中…':'确认归档'}</button><button disabled={busy} onClick={()=>setMode('menu')}>取消</button></div></div>
    :<>
      <button role="menuitem" onClick={()=>{restart();onShare()}}><Share2 size={15}/>分享会话</button>
      <button role="menuitem" onClick={()=>copy(nativeId,'会话 ID')}><Copy size={15}/>复制会话 ID</button>
      {cwd&&<button role="menuitem" onClick={()=>copy(cwd,'工作目录')}><Copy size={15}/>复制工作目录</button>}
      {canManage&&<button role="menuitem" onClick={()=>{setDraft(title);setMode('rename')}}><Pencil size={15}/>重命名</button>}
      {canManage&&<button role="menuitem" onClick={()=>setMode('archive')}><Archive size={15}/>归档（从列表隐藏）</button>}
      <button role="menuitem" onClick={()=>{restart();onDelete()}}><Trash2 size={15}/>删除会话</button>
      <button role="menuitem" onClick={()=>{restart();onInfo()}}><Info size={15}/>会话信息</button>
      {note&&<p className="session-menu-note">{note}</p>}
     </>}
  </div>}
 </div>;
}
