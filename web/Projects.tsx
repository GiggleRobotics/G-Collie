import React,{useEffect,useState} from 'react';
import {Folder,ChevronRight,RefreshCw} from 'lucide-react';
import AgentIcon from './AgentIcon';
export default function Projects({api,projects,onSelect}:{api:(p:string)=>Promise<any>;projects:any[];onSelect:(path:string)=>void}){
 const[usage,setUsage]=useState<any>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 async function load(){setBusy(true);try{setUsage(await api('/usage'));setError('')}catch{setError('项目用量暂时未能读取，请重试')}finally{setBusy(false)}}
 useEffect(()=>{void load()},[]);
 function tokens(path:string,agent:string){const n=usage?.agents?.[agent]?.projects?.find((p:any)=>p.path===path)?.usage?.total;return typeof n!=='number'||n<=0?'—':n>=1e6?(n/1e6).toFixed(1)+'M':n>=1e3?(n/1e3).toFixed(0)+'K':String(n)}
 return <section className="chat-page desktop-projects"><div className="section-heading"><div><h1>项目管理</h1><p className="muted">{projects.length} 个项目 · 本机累计用量</p></div><button className="icon-button" aria-label="刷新项目用量" disabled={busy} onClick={load}><RefreshCw size={20} className={busy?'spinning':''}/></button></div>{error&&<p role="alert">{error}</p>}<div className="project-grid">{projects.map(p=><button className="desktop-project-card" key={p.path} onClick={()=>onSelect(p.path)}><div className="project-card-heading"><Folder size={21}/><strong>{p.name}</strong><ChevronRight size={18}/></div><div className="project-card-summary"><span>{p.sessions} 个会话</span><div className="project-token-slots">{['Codex','Hermes','Claude Code'].map(a=><span key={a} title={a+' · 本机累计 Token'}><AgentIcon agent={a}/><span>{tokens(p.path,a)}</span></span>)}</div></div></button>)}</div>{!projects.length&&<p className="muted">暂无关联项目</p>}<p className="project-explanation muted">用量来自当前电脑的可解析记录；未记录或为零时显示 —。</p></section>
}
