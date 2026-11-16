// Formal dist + intercepted API only: no real credentials, agents, sessions or writes.
import {chromium,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
const version=JSON.parse(readFileSync(new URL('../package.json',import.meta.url))).version;
const browser=await chromium.launch();
try {
 const context=await browser.newContext(),page=await context.newPage();
 const errors=[],writes=[];let agent='Codex',status='running',fail=true,releaseCapabilities;
 page.on('pageerror',e=>errors.push(e.message));
 const session=()=>({id:'test:fixture',nativeId:'fixture',agent,title:'隔离回归会话',updatedAt:Date.now(),project:'测试'});
 await context.route('**/api/**',async route=>{
  const req=route.request(),path=decodeURIComponent(new URL(req.url()).pathname.slice(4));
  if(req.method()==='POST')writes.push({path,body:req.postDataJSON()});
  if(path.startsWith('/usage'))return route.fulfill(fail?{status:500,json:{error:'隔离用量读取失败'}}:{json:{agents:{},projects:[],daily:[]}});
  if((path==='/schedules'||path.endsWith('/resources'))&&fail)return route.fulfill({status:500,json:{error:'隔离测试读取失败'}});
  if(path.endsWith('/codex-capabilities')){await new Promise(resolve=>releaseCapabilities=resolve);return route.fulfill({json:{goal:{data:{goal:{objective:'已存目标'}}},skills:[],modes:{data:{data:[]}}}});}
  let data={};
  if(path==='/auth/status')data={paired:true,device:{role:'owner'}};
  else if(path==='/local')data={sessions:[session()],projects:[],warnings:[]};
  else if(path==='/local/test:fixture')data={...session(),desktopLive:true,desktopControl:true,hermesLive:agent==='Hermes',claudeLive:agent==='Claude Code',status,turnId:'turn',events:[{id:'a',role:'assistant',text:'隔离结果'}]};
  else if(path==='/devices')data={devices:[{id:'fixture-phone',name:'隔离测试手机',role:'control'}]};
  else if(path==='/diagnostics/requests')data={requests:[]};
  else if(path==='/schedules')data={tasks:[]};
  else if(path.endsWith('/resources'))data={resources:[]};
  await route.fulfill({json:data});
 });
 async function open(){await page.goto(process.env.GCOLLIE_UI_TEST_URL||'http://127.0.0.1:4397');await page.locator('.history-link').first().click();await expect(page.getByText('隔离结果',{exact:true})).toBeVisible();}
 for(agent of ['Codex','Hermes']){
  await open();const input=page.getByRole('textbox',{name:'消息输入',exact:true});await expect(input).toBeEnabled();
  await input.fill(agent+' 追加测试');await page.getByRole('button',{name:'追加消息',exact:true}).click();await expect(input).toHaveValue('');
  if(!writes.some(w=>w.path===(agent==='Hermes'?'/hermes/fixture':'/desktop/fixture')&&w.body.text===agent+' 追加测试'))throw Error('append route '+agent);
  await expect(page.getByRole('button',{name:'停止当前轮',exact:true})).toBeEnabled();
  await page.setViewportSize({width:390,height:844});
  const appendBox=await page.getByRole('button',{name:'追加消息',exact:true}).boundingBox(),stopBox=await page.getByRole('button',{name:'停止当前轮',exact:true}).boundingBox();
  if(!appendBox||!stopBox||appendBox.x+appendBox.width>stopBox.x||await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('running composer mobile layout');
  await page.setViewportSize({width:1280,height:800});
 }
 agent='Codex';status='idle';await open();await page.getByRole('button',{name:'添加附件',exact:true}).click();await page.getByRole('menuitem',{name:'目标、计划与插件',exact:true}).click();
 await expect(page.getByRole('textbox',{name:'持续目标',exact:true})).toBeDisabled();await expect.poll(()=>!!releaseCapabilities).toBe(true);releaseCapabilities();
 await expect(page.getByRole('textbox',{name:'持续目标',exact:true})).toHaveValue('已存目标');await page.getByRole('textbox',{name:'持续目标',exact:true}).fill('用户新目标');await expect(page.getByRole('button',{name:'保存目标',exact:true})).toBeEnabled();await page.getByRole('button',{name:'关闭能力设置',exact:true}).click();
 status='running';agent='Claude Code';await open();await expect(page.getByRole('textbox',{name:'消息输入',exact:true})).toBeDisabled();await expect(page.getByRole('button',{name:'追加消息',exact:true})).toHaveCount(0);
 agent='Codex';status='waiting';await open();await page.getByRole('textbox',{name:'消息输入',exact:true}).fill('等待中追加测试');await page.getByRole('button',{name:'追加消息',exact:true}).click();await expect(page.getByRole('textbox',{name:'消息输入',exact:true})).toHaveValue('');
 if(!writes.some(w=>w.path==='/desktop/fixture'&&w.body.text==='等待中追加测试'))throw Error('waiting steer route');
 for(const [a,s] of [['Codex','starting'],['Hermes','waiting']]){agent=a;status=s;await open();await expect(page.getByRole('textbox',{name:'消息输入',exact:true})).toBeDisabled();}
 await page.getByRole('button',{name:'定时任务',exact:true}).click();await expect(page.getByRole('alert')).toContainText('隔离测试读取失败');await expect(page.getByText('暂无定时任务',{exact:true})).toHaveCount(0);
 fail=false;await page.getByRole('button',{name:'重试',exact:true}).click();await expect(page.getByText('暂无定时任务',{exact:true})).toBeVisible();
 await page.getByRole('button',{name:'下载内容',exact:true}).click();fail=true;
 await page.getByRole('button',{name:'来源会话',exact:true}).click();await page.locator('.session-picker-options button').first().click();await expect(page.getByRole('alert')).toContainText('隔离测试读取失败');await expect(page.getByText('这段会话暂无可下载文件',{exact:true})).toHaveCount(0);
 fail=false;await page.getByRole('button',{name:'重试',exact:true}).click();await expect(page.getByText('这段会话暂无可下载文件',{exact:true})).toBeVisible();
 fail=true;await page.getByRole('button',{name:'用量统计',exact:true}).click();await expect(page.getByRole('alert')).toContainText('隔离用量读取失败');await expect(page.getByText('暂无可用统计',{exact:true})).toHaveCount(0);await expect(page.getByText('正在建立本地用量索引…',{exact:true})).toHaveCount(0);fail=false;await page.getByRole('button',{name:'刷新用量统计',exact:true}).click();await expect(page.getByText('暂无可用统计',{exact:true})).toBeVisible();
 await page.getByRole('button',{name:'服务端管理',exact:true}).click();await page.getByRole('button',{name:'手机日志',exact:true}).click();
 for(const width of [1440,1264,1024,768,390]){
  await page.setViewportSize({width,height:900});
  const layout=await page.locator('.diag-phone').evaluate(el=>{const h=el.querySelector('h2').getBoundingClientRect(),p=el.querySelector('p').getBoundingClientRect(),fields=el.querySelector('.diag-fields').getBoundingClientRect();return{display:getComputedStyle(el).display,title:h.width,stacked:p.top>=h.bottom,fields:fields.top>=p.bottom,inputs:[...el.querySelectorAll('input')].map(i=>i.getBoundingClientRect().width),overflow:document.documentElement.scrollWidth>innerWidth}});
  if(layout.display!=='block'||layout.title<100||!layout.stacked||!layout.fields||layout.inputs.some(w=>w<230)||layout.overflow)throw Error('diagnostic form layout '+width+JSON.stringify(layout));
 }
 await page.setViewportSize({width:1280,height:800});
 await page.getByRole('button',{name:'我的工作台设置'}).click();await page.getByRole('menuitem',{name:'关于 G-Collie',exact:true}).click();await expect(page.getByText(`内测版 ${version} · By Giggle`,{exact:true})).toBeVisible();
 if(errors.length)throw Error(errors.join('\n'));
 console.log('PASS current dist: Codex/Hermes append + stop; Codex waiting steer; Claude/starting/Hermes-waiting guarded; schedule/download/usage error/retry; goal loading guard; package version');
}finally{await browser.close();}
