import type {Express} from 'express';
import express from 'express';
import {randomBytes,randomUUID} from 'node:crypto';

// Auth middleware runs before these routes. No files or assistant calls are involved.
export function installNetworkTest(app:Express, device:(res:any)=>string){
 const tests=new Map<string,{device:string;until:number;pings:number;download:boolean;upload:boolean}>();
 const last=new Map<string,number>(),payload=randomBytes(1024*1024);
 app.post('/api/diagnostics/network/start',(_req,res)=>{
  const key=device(res),now=Date.now();
  for(const[id,t]of tests)if(t.until<now)tests.delete(id);
  for(const[id,time]of last)if(now-time>60000)last.delete(id);
  if(now-(last.get(key)||0)<20000){res.status(429).set('Retry-After','20').json({error:'请稍候再测试，避免重复消耗流量'});return}
  last.set(key,now);const id=randomUUID();tests.set(id,{device:key,until:now+30000,pings:0,download:false,upload:false});
  res.json({id,bytes:payload.length,maxSeconds:20});
 });
 const lookup=(req:any,res:any)=>{const t=tests.get(String(req.params.id));if(!t||t.device!==device(res)||t.until<Date.now()){res.status(404).json({error:'测试已结束或不属于此设备'});return}return t};
 app.get('/api/diagnostics/network/:id/ping',(req,res)=>{const t=lookup(req,res);if(!t)return;if(++t.pings>6){res.status(429).json({error:'采样已完成'});return}res.json({ok:true})});
 app.get('/api/diagnostics/network/:id/download',(req,res)=>{const t=lookup(req,res);if(!t)return;if(t.download){res.status(409).json({error:'下载采样已完成'});return}t.download=true;res.type('application/octet-stream').set('Content-Length',String(payload.length)).send(payload)});
 app.post('/api/diagnostics/network/:id/upload',express.raw({type:'application/octet-stream',limit:'1mb'}),(req,res)=>{const t=lookup(req,res);if(!t)return;if(t.upload){res.status(409).json({error:'上传采样已完成'});return}if(!Buffer.isBuffer(req.body)||req.body.length!==payload.length){res.status(400).json({error:'测速数据长度不正确'});return}t.upload=true;res.json({bytes:req.body.length})});
}
