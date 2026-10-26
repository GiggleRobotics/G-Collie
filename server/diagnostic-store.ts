import type {Express} from 'express';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
const week=7*86400000;
const identifier=(v:any)=>typeof v==='string'&&/^[a-zA-Z0-9_.:/-]{1,180}$/.test(v)?v:undefined;
export function diagnosticRows(rows:any){
 if(!Array.isArray(rows)||rows.length>1000)throw Error('诊断记录数量超过限制');
 return rows.map(e=>{const time=Date.parse(e?.time);if(!Number.isFinite(time)||time<Date.now()-week||time>Date.now()+60000)throw Error('日志时间超出最近 7 天');return{time:new Date(time).toISOString(),route:identifier(e.route)||'unknown',category:identifier(e.category)||'unknown',requestId:identifier(e.requestId),durationMs:typeof e.durationMs==='number'?Math.max(0,Math.min(120000,e.durationMs)):undefined,status:Number.isInteger(e.status)?e.status:undefined}});
}
export function diagnosticRange(body:any){const from=Date.parse(body.from),to=Date.parse(body.to);if(!Number.isFinite(from)||!Number.isFinite(to)||from>to||from<Date.now()-week||to>Date.now()+60000)throw Error('请选择最近 7 天内的有效时间段');return{from,to}}
export class DiagnosticStore{
 private path:string;private data:{events:any[];packs:any[];requests:any[]}={events:[],packs:[],requests:[]};private sampled=new Map<string,number>();
 constructor(dir:string){this.path=join(dir,'diagnostic-history.json');try{const d=JSON.parse(readFileSync(this.path,'utf8'));if(Array.isArray(d.events)&&Array.isArray(d.packs)&&Array.isArray(d.requests))this.data=d}catch{}}
 private save(){const cutoff=Date.now()-week;this.data.events=this.data.events.filter(e=>Date.parse(e.time)>cutoff).slice(-3000);this.data.packs=this.data.packs.filter(p=>Date.parse(p.time)>cutoff).slice(-30);while(Buffer.byteLength(JSON.stringify(this.data.packs))>10*1024*1024)this.data.packs.shift();this.data.requests=this.data.requests.filter(r=>r.createdAt>cutoff).slice(-100);writeFileSync(this.path+'.tmp',JSON.stringify(this.data),{mode:0o600});renameSync(this.path+'.tmp',this.path)}
 record(e:any){const key=e.method+':'+e.route;if(e.status<400&&e.durationMs<2000){if(Date.now()-(this.sampled.get(key)||0)<60000)return;this.sampled.set(key,Date.now())}this.data.events.push({...e,time:new Date().toISOString()});this.save()}
 events(from:number,to:number){return this.data.events.filter(e=>Date.parse(e.time)>=from&&Date.parse(e.time)<=to)}
 request(device:string,from:number,to:number){const active=this.data.requests.find(r=>r.device===device&&!r.completedAt&&r.expiresAt>Date.now());if(active)return active;const r={id:randomUUID(),device,from,to,createdAt:Date.now(),expiresAt:Date.now()+30*60000};this.data.requests.push(r);this.save();return r}
 pending(device:string){return this.data.requests.filter(r=>r.device===device&&!r.completedAt&&r.expiresAt>Date.now()).map(({id,from,to})=>({id,from,to}))}
 upload(device:string,body:any){const rows=diagnosticRows(body.events),range=diagnosticRange(body);let request;if(body.requestId){request=this.data.requests.find(r=>r.id===body.requestId&&r.device===device);if(!request||request.expiresAt<Date.now())throw Error('日志获取请求已过期或不属于此设备');if(request.completedAt)return{id:request.packId};if(range.from!==request.from||range.to!==request.to)throw Error('日志时段与请求不匹配')}
 const pack={id:randomUUID(),device,time:new Date().toISOString(),from:range.from,to:range.to,events:rows.filter(e=>Date.parse(e.time)>=range.from&&Date.parse(e.time)<=range.to)};this.data.packs.push(pack);if(request){request.completedAt=Date.now();request.packId=pack.id}this.save();return{id:pack.id}}
 list(){return this.data.requests.map(r=>({...r,status:r.completedAt?'completed':r.expiresAt<Date.now()?'expired':'waiting-device'}))}
 packs(device:string,from:number,to:number){return this.data.packs.filter(p=>p.device===device&&p.to>=from&&p.from<=to).map(p=>({...p,events:p.events.filter((e:any)=>Date.parse(e.time)>=from&&Date.parse(e.time)<=to)}))}
}
export function installDiagnostics(app:Express,store:DiagnosticStore,device:(res:any)=>string,isActive:(id:string)=>boolean){
 const owner=(res:any)=>{if(res.locals.role!=='owner'){res.status(403).json({error:'仅电脑管理端可获取设备日志'});return false}return true};
 app.get('/api/diagnostics/requests/pending',(_req,res)=>res.json({requests:store.pending(device(res))}));
 app.post('/api/diagnostics/phone',(req,res)=>{try{res.json(store.upload(device(res),req.body))}catch(e){res.status(400).json({error:(e as Error).message})}});
 app.post('/api/diagnostics/requests',(req,res)=>{if(!owner(res))return;try{if(typeof req.body.device!=='string'||!isActive(req.body.device))throw Error('设备未配对或授权已撤销');const r=diagnosticRange(req.body);res.json(store.request(req.body.device,r.from,r.to))}catch(e){res.status(400).json({error:(e as Error).message})}});
 app.get('/api/diagnostics/requests',(_req,res)=>{if(owner(res))res.json({requests:store.list()})});
 app.get('/api/diagnostics/bundle',(req,res)=>{if(!owner(res))return;try{const range=diagnosticRange(req.query);res.json({from:range.from,to:range.to,computer:store.events(range.from,range.to),phone:typeof req.query.device==='string'?store.packs(req.query.device,range.from,range.to):[]})}catch(e){res.status(400).json({error:(e as Error).message})}});
}
