import React from 'react';
import {Terminal,ChevronRight,Lightbulb} from 'lucide-react';
export default function ProcessRecord({record:e,live,children}:{record:any;live:boolean;children?:React.ReactNode}) {
 const [expanded,setExpanded]=React.useState(false);
 const thought=e.role==='reasoning', pending=e.status==='pending';
 const command=e.commands?.[0]?.command||e.input||e.name||'工具';
 const title=thought?(pending&&live?'正在思考':'已思考'):
   `${e.status==='failed'?'执行失败':pending?(live?'正在运行':'结果未记录'):e.status==='submitted'?'已提交':'已运行'} ${String(command).split('\n')[0]}`;
 const text=e.commands?.length?e.commands.map((c:any)=>`${c.command}\n${c.output||''}`).join('\n\n'):
   [e.input,e.text].filter(Boolean).join('\n\n');
 if(thought&&!String(text||'').trim())return <div className="tool-disclosure"><span><Lightbulb size={15}/>{title}</span></div>;
 return <details className="tool-disclosure" onToggle={children?event=>setExpanded(event.currentTarget.open):undefined}><summary>{thought?<Lightbulb size={15}/>:<Terminal size={15}/>}<span>{title.slice(0,100)}</span><ChevronRight size={14}/></summary><pre>{text||'暂无详细记录'}</pre>{expanded&&children}</details>;
}
