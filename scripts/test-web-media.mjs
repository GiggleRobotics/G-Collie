import {chromium} from '@playwright/test';import fs from 'node:fs';
const browser=await chromium.launch(),context=await browser.newContext(),page=await context.newPage({viewport:{width:1280,height:800}});const errors=[],resourceReads=[];page.on('pageerror',e=>errors.push(e.message));const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAFUlEQVR4nGM0mxHJwMDAwMDAxAADABTXASsGnEG9AAAAAElFTkSuQmCC','base64');const sessions=[{id:'hermes:current',nativeId:'current',agent:'Hermes',title:'媒体回归',project:'demo',updatedAt:Date.now(),archived:false},{id:'hermes:foreign',agent:'Hermes',title:'其他会话',updatedAt:Date.now()-100,archived:false}];const resources=[{id:'a',ref:'/a.png',name:'第一张',image:true},{id:'b',ref:'/b.png',name:'第二张',image:true},{id:'v',ref:'/v.mp4',name:'会话视频.mp4',image:false}];
const base=process.env.GCOLLIE_UI_TEST_URL||'http://127.0.0.1:5179';
const remoteImage=new URL('/synthetic-remote.png',base).href;
let includeToolAndRemote=false;
await context.route('**/synthetic-remote.png',route=>route.fulfill({contentType:'image/png',body:png}));
async function checkOriginalImage(message){
 const image=message.locator('.session-image-open img');
 await image.waitFor();
 const decoded=im=>im.decode().then(()=>[im.naturalWidth,im.naturalHeight].join('x'));
 if(await image.evaluate(decoded)!=='3x2')throw Error('original message did not decode the expected image');
 await message.locator('.session-image-open').click();
 const dialog=page.locator('.session-media-browser[open]');
 if(await dialog.locator('.session-image-viewport img').evaluate(decoded)!=='3x2')throw Error('full image failed to decode');
 await dialog.getByRole('button',{name:'关闭媒体预览'}).click();
}
await context.route('**/preview/**',r=>r.fulfill({body:r.request().url().includes('/v/')?fs.readFileSync('flutter_client/assets/ui/demo-video.mp4'):png,contentType:r.request().url().includes('/v/')?'video/mp4':'image/png'}));
await context.route('**/api/**',async route=>{const path=decodeURIComponent(new URL(route.request().url()).pathname.slice(4));let data={};if(path==='/auth/status')data={paired:true,device:{role:'owner'}};else if(path==='/local')data={sessions,projects:[],warnings:[]};else if(path.includes('/resources')){resourceReads.push(path);if(path.endsWith('/preview'))data={path:'/preview/'+path.split('/').at(-2)+'/view'};else if(path.endsWith('/poster'))return route.fulfill({body:png,contentType:'image/png'});else data={resources}}else if(path.startsWith('/local/'))data={...sessions[0],desktopLive:true,desktopControl:true,historyLimit:200,status:'idle',events:[{id:'image',role:'assistant',text:'会话内媒体',media:['/a.png','/b.png','/v.mp4']},{id:'single',role:'user',text:'本条只有一张图片',media:['/b.png']},...(includeToolAndRemote?[{id:'tool',role:'tool',name:'查看示例',text:'带图片的工具结果',media:['/a.png']},{id:'remote',role:'assistant',text:'结构化网址图片',media:[remoteImage]},{id:'both',role:'assistant',text:'重复引用：![示例]('+remoteImage+')',media:[remoteImage]}]:[])]};await route.fulfill({json:data})});
try{await page.goto(process.env.GCOLLIE_UI_TEST_URL||'http://127.0.0.1:5179');await page.locator('.welcome-shortcuts button').nth(1).click();await page.locator('.recent-conversations>button').first().click();await page.getByText('本条只有一张图片',{exact:true}).waitFor();if(await page.locator('article.user .session-image-thumbnails').count())throw Error('single message inherited thumbnails');await page.getByRole('button',{name:'查看图片：第一张',exact:true}).click();await page.getByRole('dialog').waitFor();await page.getByRole('button',{name:'下一个媒体',exact:true}).click();await page.getByText('第二张 · 2 / 3').waitFor();await page.keyboard.press('ArrowRight');await page.locator('.session-media-browser video').waitFor();if(await page.getByRole('button',{name:'下一个媒体',exact:true}).isEnabled())throw Error('last item overflow');await page.keyboard.press('ArrowLeft');await page.getByText('第二张 · 2 / 3').waitFor();await page.locator('.session-media-browser video').waitFor({state:'detached'});if(await page.locator('.session-media-browser video').count())throw Error('previous video remains');await page.getByRole('button',{name:'关闭媒体预览',exact:true}).click();await page.locator('.chat-composer').waitFor();if(resourceReads.some(p=>p.includes('foreign')))throw Error('cross-session leak');includeToolAndRemote=true;
await page.reload();
const tool=page.locator('.tool-disclosure').filter({hasText:'带图片的工具结果'});
await tool.locator('summary').click();
await checkOriginalImage(tool);
const remote=page.locator('.chat-message').filter({hasText:'结构化网址图片'});
await checkOriginalImage(remote);
const both=page.locator('.chat-message').filter({hasText:'重复引用'});
if(await both.locator('.session-image-open').count()!==1)throw Error('structured and Markdown copies both displayed');
if(errors.length)throw Error(errors.join('\n'));console.log('PASS: session media paging, video disposal, boundaries and session isolation');}finally{await browser.close()}
