import React,{useEffect,useRef,useState} from 'react';
const pad=(n:number)=>String(n).padStart(2,'0');
function Wheel({count,value,onChange,label}:{count:number;value:number;onChange:(v:number)=>void;label:string}){
 const ref=useRef<HTMLDivElement>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 useEffect(()=>{if(ref.current)ref.current.scrollTop=value*44;return()=>clearTimeout(timer.current)},[]);
 function select(n:number){const v=Math.max(0,Math.min(count-1,n));ref.current?.scrollTo({top:v*44,behavior:'smooth'});onChange(v)}
 return <div ref={ref} className="time-wheel-column" role="listbox" aria-label={label} tabIndex={0} onKeyDown={e=>{if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();select(value+(e.key==='ArrowDown'?1:-1))}if(e.key==='Home'||e.key==='End'){e.preventDefault();select(e.key==='Home'?0:count-1)}}} onScroll={()=>{clearTimeout(timer.current);timer.current=setTimeout(()=>{if(ref.current)onChange(Math.max(0,Math.min(count-1,Math.round(ref.current.scrollTop/44))))},100)}}>{Array.from({length:count},(_,n)=><div role="option" aria-selected={value===n} className={value===n?'selected':''} key={n} onClick={()=>select(n)}>{pad(n)}</div>)}</div>
}
export default function TimeWheel({hour,minute,onConfirm}:{hour:number;minute:number;onConfirm:(h:number,m:number)=>void}){
 const[h,setH]=useState(hour),[m,setM]=useState(minute);
 return <div className="time-wheel-panel"><div className="time-wheel-labels"><span>小时</span><span>分钟</span></div><div className="time-wheel-body"><div className="time-wheel-highlight"/><Wheel count={24} value={h} onChange={setH} label="选择小时"/><span className="wheel-colon">:</span><Wheel count={60} value={m} onChange={setM} label="选择分钟"/></div><div className="time-wheel-footer"><span>{pad(h)} : {pad(m)}</span><button type="button" onClick={()=>onConfirm(h,m)}>确定</button></div></div>
}
