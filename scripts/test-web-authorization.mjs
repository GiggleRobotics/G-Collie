import {chromium,expect} from '@playwright/test';
const browser=await chromium.launch();
try{
 const page=await browser.newPage();let role='owner',paired=true,statusCalls=0;
 await page.route('**/api/**',async route=>{const path=decodeURIComponent(new URL(route.request().url()).pathname.slice(4));let data={};if(path==='/auth/status'){statusCalls++;data={paired,device:paired?{role}:null};}else if(path==='/local')data={sessions:[{id:'codex:fixture',nativeId:'fixture',agent:'Codex',title:'隔离权限',updatedAt:Date.now()}],projects:[],warnings:[]};else if(path.startsWith('/local/'))data={id:'codex:fixture',nativeId:'fixture',agent:'Codex',desktopLive:true,desktopControl:true,status:'idle',events:[{id:'a',role:'assistant',text:'隔离内容'}]};await route.fulfill({json:data});});
 await page.goto(process.env.GCOLLIE_UI_TEST_URL||'http://127.0.0.1:4397');await page.locator('.history-link').first().click();await expect(page.getByRole('textbox',{name:'消息输入',exact:true})).toBeEnabled();
 role='view';await page.evaluate(()=>window.dispatchEvent(new Event('focus')));await expect(page.getByRole('textbox',{name:'消息输入（只读）',exact:true})).toBeDisabled();await expect(page.getByRole('button',{name:'服务端管理',exact:true})).toHaveCount(0);
 role='control';await page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await expect(page.getByRole('textbox',{name:'消息输入',exact:true})).toBeEnabled();
 paired=false;await page.evaluate(()=>window.dispatchEvent(new Event('focus')));await expect(page.getByRole('heading',{name:'配对你的电脑',exact:true})).toBeVisible();await expect(page.getByRole('alert')).toContainText('授权已失效');if(statusCalls<4)throw Error('authorization not refreshed');
 console.log('PASS no reload: owner → view → control; focus/foreground sync; revoked pairing returns to pair screen');
}finally{await browser.close();}
