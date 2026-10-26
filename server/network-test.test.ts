import test from 'node:test';import assert from 'node:assert/strict';import express from 'express';import {installNetworkTest}from './network-test.js';
test('network test bounds transfers and isolates sessions per paired device',async()=>{
 const app=express();app.use((req,res,next)=>{res.locals.device=req.header('x-test-device')||'a';next()});installNetworkTest(app,r=>r.locals.device);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.on('listening',r));const port=(server.address() as any).port,base=`http://127.0.0.1:${port}/api/diagnostics/network`;
 try{
  const start:any=await(await fetch(base+'/start',{method:'POST'})).json();assert.equal(start.bytes,256*1024);
  assert.equal((await fetch(base+'/start',{method:'POST'})).status,429);
  assert.equal((await fetch(`${base}/${start.id}/ping`,{headers:{'x-test-device':'b'}})).status,404);
  for(let i=0;i<6;i++)assert.equal((await fetch(`${base}/${start.id}/ping`)).status,200);
  assert.equal((await fetch(`${base}/${start.id}/ping`)).status,429);
  assert.equal((await(await fetch(`${base}/${start.id}/download`)).arrayBuffer()).byteLength,256*1024);
  assert.equal((await fetch(`${base}/${start.id}/download`)).status,409);
  assert.equal((await fetch(`${base}/${start.id}/upload`,{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:Buffer.alloc(256*1024)})).status,200);
  assert.equal((await fetch(`${base}/${start.id}/upload`,{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:Buffer.alloc(256*1024)})).status,409);
  const second=await fetch(base+'/start',{method:'POST'});assert.equal(second.status,200);const next:any=await second.json();assert.notEqual(next.id,start.id);assert.equal((await fetch(`${base}/${next.id}/ping`)).status,200);
 }finally{server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()))}
});
