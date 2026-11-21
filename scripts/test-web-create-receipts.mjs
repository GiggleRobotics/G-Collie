// Exercise the built Web UI. All API traffic is intercepted, including writes.
import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
import {join} from 'node:path';

const url=process.env.GCOLLIE_UI_TEST_URL||'http://127.0.0.1:4397';
const browser=await chromium.launch();
const evidence=process.env.GCOLLIE_UI_EVIDENCE;
if(evidence)await mkdir(evidence,{recursive:true});
async function screenshot(page,name){
 if(evidence)await page.screenshot({animations:'disabled',path:join(evidence,name+'.png')});
}
const row={id:'hermes:existing',nativeId:'existing',agent:'Hermes',title:'已有会话',cwd:'',project:'无项目',updatedAt:1,events:[],desktopLive:true,desktopControl:true,hermesLive:true,status:'idle'};
async function scenario(name,exercise){
 const page=await browser.newPage({viewport:{width:1440,height:900},serviceWorkers:'block'});
 const calls={creates:[],receipts:[],details:[],activations:[],errors:[]};
 const created={...row,id:'hermes:fixture:created.1',nativeId:'fixture:created.1',title:'新建已确认'};
 let readReceipt,respondToPost=route=>route.fulfill({status:409,json:{outcome:'sending',error:'正在提交'}}),
     receipt={state:'sending'},detailStatus=200,role='owner';
 page.on('pageerror',e=>calls.errors.push(e.message));
 await page.route('**/api/**',async route=>{
  const req=route.request(),path=decodeURIComponent(new URL(req.url()).pathname.slice(4));
  if(path==='/sessions'){calls.creates.push(req.postDataJSON());return respondToPost(route)}
  if(path.startsWith('/sessions/requests/')){
   calls.receipts.push(path.slice('/sessions/requests/'.length));
   return readReceipt?readReceipt(route):route.fulfill({json:receipt});
  }
  if(path.endsWith('/activate'))calls.activations.push(path);
  if(path==='/local/'+created.id||path==='/local/'+row.id){
   calls.details.push(path);
   if(path==='/local/'+created.id&&detailStatus!==200)return route.fulfill({status:detailStatus,json:{error:'读取详情失败'}});
   return route.fulfill({json:path==='/local/'+row.id?row:created});
  }
  if(path==='/attachments'){
   const body=req.postDataJSON();
   return route.fulfill({json:{id:body.image?'test-image':'test-file',name:body.name,size:1,mime:body.image?'image/png':'text/plain',image:!!body.image}});
  }
  if(path==='/attachments/test-image')return route.fulfill({contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAFhAH/gWiTEwAAAABJRU5ErkJggg==','base64')});
  const data={'/auth/status':{paired:true,device:{role}},'/local':{sessions:[row],projects:[],warnings:[]},
              '/devices':{devices:[]}};
  return route.fulfill({json:data[path]||{}});
 });
 const send=page.getByRole('button',{name:'发送消息',exact:true});
 const input=page.locator('.chat-composer textarea');
 const refresh=page.getByRole('button',{name:'刷新会话',exact:true});
 try{
  await page.goto(url);
  await page.locator('.home-new-session').click();
  await page.locator('.new-chat-agents button').nth(1).click();
  await page.getByRole('button',{name:'开始会话',exact:true}).click();
  await input.fill('首条正文');
  await exercise({page,input,send,refresh,calls,created,
   post:handler=>{respondToPost=handler},read:handler=>{readReceipt=handler},
   setReceipt:value=>{receipt=value},
   setRole:async value=>{role=value;await page.evaluate(()=>window.dispatchEvent(new Event('focus')))},
   detailFailure:code=>{detailStatus=code}
  });
  assert.deepEqual(calls.errors,[]);
  console.log('PASS',name);
 }finally{await page.close()}
}

try{
 await scenario('lost response keeps text and attachments, reads original receipt and opens once',async({page,input,send,refresh,calls,created,post,setReceipt})=>{
  post(route=>route.abort('failed'));
  await page.getByLabel('选择文件',{exact:true}).setInputFiles({name:'proof.txt',mimeType:'text/plain',buffer:Buffer.from('x')});
  await expect(page.getByText('proof.txt',{exact:true})).toBeVisible();
  await send.click();
  await expect.poll(()=>calls.receipts.length).toBeGreaterThan(0);
  await expect(input).toHaveValue('首条正文');
  await expect(send).toBeDisabled();
  await expect(page.getByRole('button',{name:'移除附件 proof.txt'})).toHaveCount(0);
  await expect(page.locator('.first-send-notice')).toContainText('正在确认发送结果');
  await expect(page.locator('.first-send-notice')).toContainText('正文和附件已保留');
  await expect(page.getByText('这是尚未创建的草稿，发送第一条消息开始。')).toHaveCount(0);
  await expect(page.locator('.chat-error')).toHaveCount(0);await screenshot(page,'web-unknown');
  for(const state of ['missing','unknown']){
   setReceipt({state});
   await refresh.click();
   await expect(send).toBeDisabled();
  }
  setReceipt({state:'done',result:{id:created.id}});
  await refresh.click();
  await expect(page.locator('.desktop-session-title')).toHaveText(created.title);
  assert.equal(calls.creates.length,1);
  assert.deepEqual(calls.creates[0].attachments,['test-file']);
  assert.ok(calls.receipts.every(id=>id===calls.creates[0].requestId));
  await expect(input).toHaveValue('');
  await expect(page.getByText('proof.txt',{exact:true})).toHaveCount(0);
 });
 await scenario('only definitive refusal unlocks same draft for manual retry',async({page,input,send,calls,created,setReceipt,post})=>{
  await send.click();
  await expect.poll(()=>calls.receipts.length).toBeGreaterThan(0);
  await expect(send).toBeDisabled();
  setReceipt({state:'failed',error:'项目不可用'});
  await expect(input).toBeEditable();
  await expect(page.locator('.first-send-notice')).toContainText('项目不可用');
  await expect(page.locator('.first-send-notice')).not.toContainText('图片');
  assert.equal(calls.creates.length,1);
  await input.fill('已修正');
  post(route=>route.fulfill({json:{id:created.id}}));
  await send.click();
  await expect.poll(()=>calls.details.includes('/local/'+created.id)).toBe(true);
  assert.equal(calls.creates.length,2);
  assert.equal(calls.creates[0].requestId,calls.creates[1].requestId);
  assert.equal(calls.creates[1].prompt,'已修正');
 });
 for(const channel of ['post','receipt']){
  await scenario('invalid image via '+channel+' keeps draft editable and fences only the named attachment',async({page,input,send,calls,created,setReceipt,post,setRole})=>{
   // The mock upload intentionally accepts a 1-byte fixture. No files reach a real server.
   await page.getByLabel('选择照片',{exact:true}).setInputFiles({name:'进展截图.png',mimeType:'image/png',buffer:Buffer.from('x')});
   await expect(page.getByText('进展截图.png',{exact:true})).toBeVisible();
   await expect(page.getByRole('button',{name:'添加附件',exact:true})).toBeEnabled();
   await page.getByLabel('选择文件',{exact:true}).setInputFiles({name:'项目说明.md',mimeType:'text/plain',buffer:Buffer.from('y')});
   await expect(page.getByText('项目说明.md',{exact:true})).toBeVisible();
   const invalid={code:'session_create_invalid_image',attachmentId:'test-image',error:'图片无法读取，请移除或更换。'};
   let finish;
   post(route=>new Promise(resolve=>{
    finish=async()=>{await route.fulfill({status:409,json:channel==='post'?{...invalid,outcome:'failed'}:{outcome:'unknown',error:'回执待确认'}});resolve()};
   }));
   await page.setViewportSize({width:390,height:844});
   await send.click();await expect.poll(()=>!!finish).toBe(true);
   await expect(page.locator('.first-send-notice')).toHaveText('正在发送首条消息…');
   await expect(input).not.toBeEditable();await input.press('Enter');
   await expect(send).toBeDisabled();assert.equal(calls.creates.length,1);
   setReceipt({state:'failed',...invalid});await finish();
   await expect(page.locator('.first-send-notice')).toContainText('首条消息未发送');
   await expect(page.locator('.first-send-notice')).toContainText(invalid.error);
   await expect(page.locator('.chat-error')).toHaveCount(0);
   await expect(input).toBeEditable();await expect(send).toBeDisabled();await screenshot(page,'web-failed-narrow');
   await input.fill('已修改正文');await input.press('Enter');
   assert.equal(calls.creates.length,1);
   await page.getByRole('button',{name:'移除附件 项目说明.md'}).click();
   await expect(send).toBeDisabled();
   await setRole('view');await expect(input).toBeDisabled();await expect(page.getByRole('button',{name:'移除附件 进展截图.png'})).toBeDisabled();
   await setRole('control');await expect(input).toBeEditable();await page.getByRole('button',{name:'移除附件 进展截图.png'}).click();
   await expect(page.locator('.first-send-notice')).toContainText('可编辑草稿后重新发送');
   post(route=>route.fulfill({json:{id:created.id}}));
   await input.press('Shift+Enter');assert.equal(calls.creates.length,1);
   await input.press('Enter');await expect(page.locator('.desktop-session-title')).toHaveText(created.title);
   await expect(page.locator('.first-send-notice')).toHaveCount(0);
   assert.equal(calls.creates.length,2);assert.deepEqual(calls.creates[1].attachments,[]);
   assert.equal(calls.creates[1].requestId,calls.creates[0].requestId);
  });
 }
 await scenario('read-only device can confirm first send without activating history',async({page,input,send,refresh,setReceipt,calls,created,setRole})=>{
  await send.click();await expect.poll(()=>calls.receipts.length).toBeGreaterThan(0);
  await setRole('view');await expect(input).toBeDisabled();
  created.desktopLive=false;created.desktopControl=false;setReceipt({state:'done',result:{id:created.id}});
  await refresh.click();await expect(page.locator('.desktop-session-title')).toHaveText(created.title);
  await expect(send).toBeDisabled();assert.deepEqual(calls.activations,[]);assert.equal(calls.creates.length,1);
 });
 await scenario('unmatched attachment ID and old converter errors do not lock unrelated files',async({page,input,send,calls,post})=>{
  await page.getByLabel('选择文件',{exact:true}).setInputFiles({name:'proof.txt',mimeType:'text/plain',buffer:Buffer.from('x')});
  await expect(page.getByText('proof.txt',{exact:true})).toBeVisible();
  post(route=>route.fulfill({status:409,json:{outcome:'failed',code:'session_create_invalid_image',attachmentId:'other',error:'图片无法读取，请移除或更换。'}}));
  await send.click();await expect(page.locator('.first-send-notice')).toContainText('电脑读取图片失败');
  await expect(send).toBeEnabled();
  post(route=>route.fulfill({status:409,json:{outcome:'failed',error:'Command failed: /private/bin/ffmpeg -i /private/demo/input'}}));
  await send.click();await expect(page.locator('.first-send-notice')).toContainText('电脑处理首条消息失败');
  await expect(page.locator('body')).not.toContainText('/private/');
  assert.equal(calls.creates.length,2);await expect(input).toHaveValue('首条正文');
 });
 await scenario('malformed success stays locked and confirmed ID survives detail failure',async({page,send,refresh,calls,created,post,setReceipt,detailFailure})=>{
  post(route=>route.fulfill({json:{ok:true}}));
  await send.click();
  await expect.poll(()=>calls.receipts.length).toBeGreaterThan(0);
  await expect(send).toBeDisabled();
  detailFailure(409);setReceipt({state:'done',result:{id:created.id}});
  await refresh.click();
  await expect(page.getByText('读取详情失败',{exact:true})).toBeVisible();
  await expect(send).toBeDisabled();
  assert.equal(await page.evaluate(()=>localStorage.getItem('orbit-session')),created.id);
  detailFailure(200);await refresh.click();
  await expect(page.locator('.desktop-session-title')).toHaveText(created.title);
  assert.equal(calls.creates.length,1);
 });
 await scenario('wrong agent or empty native ID cannot consume a draft',async({page,input,send,refresh,calls,created,post,setReceipt})=>{
  post(route=>route.fulfill({json:{id:'codex:other'}}));
  await send.click();await expect.poll(()=>calls.receipts.length).toBeGreaterThan(0);
  for(const id of ['draft:leftover','claude:other','hermes:   ']){
   const before=calls.receipts.length;
   setReceipt({state:'done',result:{id}});
   await refresh.click();await expect.poll(()=>calls.receipts.length).toBeGreaterThan(before);
   await expect(input).toHaveValue('首条正文');await expect(send).toBeDisabled();
   assert.ok(!calls.details.includes('/local/'+id));
  }
  setReceipt({state:'done',result:{id:created.id}});await refresh.click();
  await expect(page.locator('.desktop-session-title')).toHaveText(created.title);
  assert.equal(calls.creates.length,1);
 });
 await scenario('late receipt after navigation leaves a new draft independently writable',async({page,input,send,calls,created,read})=>{
  let finish;
  read(route=>new Promise(resolve=>{finish=async()=>{await route.fulfill({json:{state:'done',result:{id:created.id}}});resolve()}}));
  await send.click();await expect.poll(()=>!!finish).toBe(true);
  await page.locator('.sidebar-actions button').filter({hasText:'项目管理'}).click();
  await expect(page.locator('.chat-composer')).toHaveCount(0);
  await page.getByRole('button',{name:'会话首页',exact:true}).click();
  await page.locator('.home-new-session').click();
  await page.getByRole('button',{name:'开始会话',exact:true}).click();
  await input.fill('独立新草稿');
  const response=page.waitForResponse(r=>new URL(r.url()).pathname.startsWith('/api/sessions/requests/'));
  await finish();await response;
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  await expect(send).toBeEnabled();await expect(input).toHaveValue('独立新草稿');
  assert.equal(calls.creates.length,1);assert.ok(!calls.details.includes('/local/'+created.id));
 });
 for(const destination of ['session','projects']){
  await scenario('late POST stays on '+destination,async({page,input,send,calls,created,post})=>{
   let finish;
   post(route=>new Promise(resolve=>{finish=async()=>{await route.fulfill({json:{id:created.id}});resolve()}}));
   await send.click();await expect.poll(()=>!!finish).toBe(true);
   if(destination==='session'){
    await page.getByTitle(row.title,{exact:true}).click();
    await expect(page.locator('.desktop-session-title')).toHaveText(row.title);
    await expect(input).toHaveValue('');
    await input.fill('另一个会话的草稿');
   }else{
    await page.locator('.sidebar-actions button').filter({hasText:'项目管理'}).click();
    await expect(page.locator('.chat-composer')).toHaveCount(0);
   }
   const response=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/sessions');
   await finish();await response;
   // Flush application response handlers before inspecting the visible destination.
   await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
   assert.ok(!calls.details.includes('/local/'+created.id));
   if(destination==='session')await expect(input).toHaveValue('另一个会话的草稿');
   else await expect(page.locator('.chat-composer')).toHaveCount(0);
  });
 }
}finally{await browser.close()}
