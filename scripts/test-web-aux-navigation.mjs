// Run against built static assets. All API calls are served by isolated fixtures.
import {chromium,expect} from '@playwright/test';
import {mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import assert from 'node:assert/strict';

const url=process.env.GCOLLIE_UI_TEST_URL||'http://127.0.0.1:4397';
const evidence=process.env.GCOLLIE_UI_EVIDENCE;
if(evidence)await mkdir(evidence,{recursive:true});
const browser=await chromium.launch();
try{
 const page=await browser.newPage({serviceWorkers:'block'});
 const errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const session={id:'codex:demo',nativeId:'demo',agent:'Codex',title:'隔离会话',cwd:'/demo',updatedAt:3};
 await page.route('**/api/**',route=>{
  const req=route.request(),path=decodeURIComponent(new URL(req.url()).pathname.slice(4));
  if(req.method()!=='GET')writes.push(path);
  const fixtures={'/auth/status':{paired:true,device:{role:'owner'}},'/local':{sessions:[session],projects:[],warnings:[]},
   '/local/codex:demo':{...session,events:[],desktopLive:true,desktopControl:true,status:'idle'},
   '/usage':{agents:{},generatedAt:0},'/schedules':{tasks:[]},'/devices':{devices:[]},
   '/diagnostics':{checks:[],recent:[]},'/diagnostics/requests':{requests:[]},'/network':{addresses:[],pairingAddresses:[]}};
  return route.fulfill({json:fixtures[path]||(path.endsWith('resources')?{resources:[]}:{})});
 });
 const sidebar=page.getByRole('complementary',{name:'会话导航'});
 const menu=page.getByRole('button',{name:'打开会话列表',exact:true}).filter({visible:true});
 const pages=['项目管理','用量统计','定时任务','下载内容','故障诊断','服务端管理'];
 async function choose(name){
  if(name==='故障诊断'){
   await sidebar.getByRole('button',{name:'我的工作台设置'}).click();
   await page.getByRole('menuitem',{name:'故障诊断',exact:true}).click();
  }else await sidebar.getByRole('button',{name:name==='项目管理'?/项目管理/:name,exact:name!=='项目管理'}).click();
  await expect(page.getByRole('heading',{name,exact:true})).toBeVisible();
 }
 for(const width of [390,768,1280]){
  await page.setViewportSize({width,height:850});await page.goto(url);
  for(const name of pages){
   if(width<=850)await page.getByRole('button',{name:'查看全部会话',exact:true}).click();
   await choose(name);
   if(width<=850){
    // In the narrow layout the menu shares the title row and stays inside the viewport.
    await expect(menu).toHaveCount(1);
    const box=await menu.boundingBox(),heading=await page.getByRole('heading',{name,exact:true}).boundingBox();
    assert.ok(box&&heading&&box.x<heading.x&&Math.abs(box.y-heading.y)<65);
    if(name==='项目管理'){
     const refreshIcon=await page.getByRole('button',{name:'刷新项目用量'}).locator('svg').boundingBox();
     assert.ok(refreshIcon&&refreshIcon.width>=16);
    }
    const fits=await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth);assert.equal(fits,true);
    if(evidence&&width===390&&name==='项目管理')await page.screenshot({animations:'disabled',path:join(evidence,'web-narrow-projects.png')});
    await menu.focus();await page.keyboard.press('Enter');await expect(menu).toHaveAttribute('aria-expanded','true');
    await page.keyboard.press('Escape');await expect(menu).toBeFocused();
    await expect(menu).toHaveAttribute('aria-expanded','false');
    await page.keyboard.press('Space');
   }else{await expect(menu).toHaveCount(0);await expect(sidebar).toBeVisible()}
   await sidebar.getByRole('button',{name:'会话首页',exact:true}).click();
   await expect(page.locator('.chat-welcome')).toBeVisible();
  }
  console.log('PASS',width,'six auxiliary pages and return to session home');
 }
 assert.deepEqual(writes,[]);assert.deepEqual(errors,[]);
}finally{await browser.close()}
