import releasePackage from '../package.json' with {type:'json'};
import {repairImageCaches} from './image-cache.js';
import {SessionDeletion,DeleteFailure} from './session-deletion.js';
import {hermesDeletionProvider} from './hermes-deletion.js';
import {existsSync} from 'node:fs';
import {adapterSummaries} from './adapters.js';
import {CodexOptions} from './codex-options.js';
import {nativeCodex,goalParams,installedSkills,resolveSkills} from './codex-native.js';
import {videoPoster} from './video-poster.js';
import {DiagnosticStore,installDiagnostics} from './diagnostic-store.js';
import {installNetworkTest} from './network-test.js';
import {Schedules} from './schedules.js';
import {InvalidImageAttachment,prepareAgentMedia} from './claude-media.js';
import {FolderProjects,prepareFolderThread} from './projects.js';
import {ClaudeBridge} from './claude.js';
import {SessionCreation,SessionCreateError,createNotSubmitted,sessionTitle} from './session-create.js';
import {attachmentInput} from './attachments.js';
import {references,compactReferences,compactDetail,resourceFile,installPreviews} from './resources.js';
import{UsageService,ResetService,exhaustedCodexWindows,readQuotaWithFallback,accountRevision}from'./usage.js';
import{AttachmentStore}from'./attachments.js';
import {EmbeddedNetwork} from './embedded-network.js';
import {Notifications} from './notifications.js';
import {DeviceAuth,cookieToken,localBootstrap,sameOrigin,writeDeviceCookie} from './auth.js';
import {networkStatus} from './network.js';
import QRCode from 'qrcode';
import {SessionActivation,assertActivatable} from './activation.js';
import {ShareStore,shareHTML} from './shares.js';
import {DesktopCreator} from './desktop-create.js';
import {HermesBridge,mergeHermesDetail} from './hermes.js';
import {DesktopBridge} from './desktop.js';
import {CodexAppServerBridge} from './codex-app-server.js';
import {codexBackend} from './codex-control.js';
import {CodexBridge} from './codex.js';
import {historyPage} from './history.js';
import {listLocal,detailLocal,invalidateLocal} from './local.js';
import express from 'express';

import {randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {mkdir,readFile,writeFile,rename,readdir,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {homedir,networkInterfaces} from 'node:os';
import {applyAction,seeds,type Task} from './core.js';
const app=express();const host=process.env.HOST||'127.0.0.1';const port=Number(process.env.PORT||4310);const dir=process.env.GCOLLIE_DATA_DIR||join(process.cwd(),'.data');await mkdir(dir,{recursive:true,mode:0o700});const codexOptions=new CodexOptions(dir);
const tokenPath=join(dir,'access-token');let token:string;try{token=(await readFile(tokenPath,'utf8')).trim()}catch{token=randomBytes(24).toString('hex');await writeFile(tokenPath,token,{mode:0o600})}
let tasks:Task[];try{tasks=JSON.parse(await readFile(join(dir,'tasks.json'),'utf8'))}catch{tasks=seeds()}
const history=new DiagnosticStore(dir);
const diagnosticPath=join(dir,'diagnostic-events.json');let diagnosticEvents:any[]=[];try{diagnosticEvents=JSON.parse(readFileSync(diagnosticPath,'utf8'))}catch{}
app.use((req,res,next)=>{const began=Date.now();const requestId=typeof req.headers['x-gcollie-request-id']==='string'&&/^[a-zA-Z0-9_-]{8,80}$/.test(req.headers['x-gcollie-request-id'])?req.headers['x-gcollie-request-id']:randomBytes(16).toString('hex');res.setHeader('x-gcollie-request-id',requestId);let failureCode:string|undefined;const sendJson=res.json.bind(res);res.json=(body:any)=>{if(res.statusCode>=400&&typeof body?.code==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(body.code))failureCode=body.code;return sendJson(body)};res.on('finish',()=>{try{if(!req.path.startsWith('/api/diagnostics/requests/pending'))history.record({requestId,route:req.route?.path||'unmatched',method:req.method,status:res.statusCode,durationMs:Date.now()-began,category:failureCode||'http'});}catch{}if(res.statusCode<400)return;diagnosticEvents.push({requestId,time:new Date().toISOString(),route:req.route?.path||'unmatched',method:req.method,status:res.statusCode,durationMs:Date.now()-began,code:failureCode});diagnosticEvents=diagnosticEvents.filter(r=>Date.parse(r.time)>Date.now()-7*86400000).slice(-500);try{writeFileSync(diagnosticPath,JSON.stringify(diagnosticEvents),{mode:0o600})}catch{}});next()});
const attachments=new AttachmentStore(dir);void repairImageCaches(dir).then(r=>{if(r.repaired||r.errors.length)console.log('Image cache upgrade: repaired='+r.repaired+', failed='+r.errors.length)}).catch(()=>console.warn('Image cache upgrade unavailable; source attachments retained')); const auth=new DeviceAuth(dir);const embeddedNetwork=new EmbeddedNetwork(dir,port);void embeddedNetwork.restore();
async function currentNetwork(){const n=await networkStatus(port);const embedded=embeddedNetwork.publicStatus();return{...n,embedded,pairingAddresses:[...(embedded.address?[embedded.address]:[]),...n.pairingAddresses]}}
const clients=new Set<express.Response>();let revision=0;const seen=new Map<string,number>();
async function persist(){const file=join(dir,'tasks.json');await writeFile(file+'.tmp',JSON.stringify(tasks),{mode:0o600});await rename(file+'.tmp',file)}
function broadcast(){revision++;for(const res of clients)res.write(`id: ${revision}\nevent: refresh\ndata: {}\n\n`)}
async function desktopControlEnabled(){if(process.env.ORBIT_DESKTOP_CONTROL==='0')return false;if(process.env.ORBIT_DESKTOP_CONTROL==='1')return true;try{const settings=JSON.parse(await readFile(join(dir,'settings.json'),'utf8'));if(typeof settings.codexControl==='boolean')return settings.codexControl}catch{}if(codexBackendMode==='app-server')return true;try{const v=JSON.parse(await readFile(join(dir,'desktop-control-verification.json'),'utf8'));return v.send===true&&v.stop===true}catch{return false}}
const codexBackendMode=codexBackend();
async function codexControlStatus(){const status=codexBackendMode==='app-server'?await nativeControl.status():await desktopCreator.status();return{...status,transport:'backend' in status?status.backend:'desktop',backend:codexBackendMode}}
const desktopMisses=new Map<string,number>();
const claude=new ClaudeBridge(dir,broadcast);
const hermes=new HermesBridge(dir,broadcast);
const sessionDeletion=new SessionDeletion(dir,hermesDeletionProvider(()=>hermes.active()));
const hermesMisses=new Map<string,number>();
const folderProjects=new FolderProjects(dir);
const desktopCreator=new DesktopCreator(dir,undefined,async(b,checkpoint)=>{
 if(codexBackendMode==='app-server')return nativeControl.create({...b,cwd:b.cwd||homedir()});
 let cwd:string;
 try{
  // Resolve the desktop tools before any session is prepared.
  const status=await desktopCreator.status();
  if(!status.available)throw Error(status.reason);
  cwd=b.cwd?await folderProjects.folder(b.cwd):'';
 }catch(e){throw createNotSubmitted(e,'session_create_desktop_prepare')}
 const threadId=checkpoint.prepared?.threadId??await prepareFolderThread(dir,cwd,b.title||'新会话');
 if(!checkpoint.prepared)checkpoint.savePrepared(threadId);
 try{
  if(cwd)await folderProjects.assign(threadId,cwd);
  await desktopCreator.load(threadId);
  let lastError:unknown;
  const deadline=Date.now()+8000;
  for(let attempt=0;attempt<20;attempt++){
   try{await desktop.follow(threadId);lastError=undefined;break}
   catch(e){
    lastError=e;
    if(Date.now()>=deadline||!/no-client-found|未收到桌面快照/.test(String(e)))throw e;
    await new Promise(r=>setTimeout(r,250));
   }
  }
  if(lastError)throw lastError;
 }catch(e){throw createNotSubmitted(e,'session_create_desktop_prepare')}
 const sent=await desktop.action(threadId,{action:'send',text:b.prompt,requestId:b.requestId,mediaPrepared:true,attachments:[]});
 return{threadId,turnId:sent.turnId};
});const shares=new ShareStore(dir);
const nativeControl=new CodexAppServerBridge(dir,()=>{invalidateLocal();broadcast()});
const desktop=codexBackendMode==='app-server'?nativeControl:new DesktopBridge(dir,broadcast);const notifications=new Notifications(dir,id=>auth.list().some(d=>d.id===id));
const codex=new CodexBridge(dir);codex.on('change',broadcast);
notifications.restore(async(id:string)=>{const d=await detailLocal(id);if(d.archived)return{desktopLive:false};if(id.startsWith('hermes:'))return hermes.view(d.nativeId);await desktop.follow(d.nativeId);return desktop.view(d.nativeId)});
process.once('SIGTERM',()=>{embeddedNetwork.close();notifications.close();claude.close();hermes.close();desktop.close();codex.close();process.exit(0)});process.once('SIGINT',()=>{embeddedNetwork.close();notifications.close();claude.close();hermes.close();desktop.close();codex.close();process.exit(0)});
app.use((req,res,next)=>{let path=req.path;try{path=decodeURIComponent(path)}catch{res.sendStatus(400);return}if(/(^|\/)\.data(\/|$)/.test(path)||/(^|\/)\.env[^/]*(\/|$)/.test(path)){res.sendStatus(404);return}next()});
app.get('/share/:key',(req,res)=>{const s=shares.get(req.params.key);res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex, nofollow','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'"});if(!s){res.status(404).send('分享已撤销、过期或不存在');return}res.type('html').send(shareHTML(s))});
const resourceDetail=(id:string)=>sessionHistory(id,{all:true});
const issuePreview=installPreviews(app,resourceDetail,id=>id==='local-owner'||auth.list().some(d=>d.id===id));
app.use('/api/attachments',express.json({limit:'15mb'}));
app.use('/api/diagnostics/phone',express.json({limit:'512kb'}));
app.use(express.json({limit:'64kb'}));
app.use('/api',(req,res,next)=>{res.setHeader('Cache-Control','no-store');if(!sameOrigin(req)){res.status(403).json({error:'拒绝跨站请求'});return}next()});
const deviceFor=(req:express.Request)=>auth.authenticate(cookieToken(req));
const bootstrapFor=(req:express.Request)=>localBootstrap(req)&&req.headers.authorization===`Bearer ${token}`;
app.get('/api/auth/status',(req,res)=>{const d=deviceFor(req);res.json({paired:!!d,device:d?auth.public(d):null})});
app.post('/api/auth/exchange',(req,res)=>{const existing=deviceFor(req);if(existing){res.json({device:auth.public(existing)});return}if(!bootstrapFor(req)){res.status(401).json({error:'请在电脑本机使用管理密钥，或输入设备配对码'});return}const r=auth.enroll(req.body.name||'电脑浏览器','owner');writeDeviceCookie(req,res,r.token);res.json({device:r.device})});
app.post('/api/auth/pair',(req,res)=>{try{const r=auth.pair(req.body.code,req.body.name);writeDeviceCookie(req,res,r.token);res.json({device:r.device})}catch(e){res.status(429).json({error:(e as Error).message})}});
app.use('/api',(req,res,next)=>{const d=deviceFor(req);if(!d&&!bootstrapFor(req)){res.status(401).json({error:'设备未配对、已过期或已被撤销，请重新配对'});return}res.locals.device=d;res.locals.role=d?.role||'owner';if(d?.role==='view'&&!['GET','HEAD'].includes(req.method)&&!req.path.startsWith('/push/')&&!['/auth/logout','/diagnostics/network/start','/diagnostics/phone'].includes(req.path)&&!/^\/diagnostics\/network\/[a-f0-9-]+\/upload$/.test(req.path)&&!/^\/local\/[^/]+\/resources\/[a-f0-9]{32}\/preview$/.test(req.path)){res.status(403).json({error:'此设备为只读权限，不能控制任务'});return}next()});
const ownerOnly=(req:express.Request,res:express.Response,next:express.NextFunction)=>{if(res.locals.role!=='owner'){res.status(403).json({error:'请在电脑管理端执行此操作'});return}next()};
const attachmentDevice=(res:express.Response)=>res.locals.device?.id||'local-owner';
installNetworkTest(app,attachmentDevice);
installDiagnostics(app,history,attachmentDevice,id=>auth.list().some(d=>d.id===id));
app.get('/api/local/:id/codex-capabilities',async(req,res)=>{try{const d=await detailWithCreated(req.params.id);if(d.agent!=='Codex')throw Error('仅 Codex 会话支持');const results=await Promise.allSettled([nativeCodex(dir,'collaborationMode/list',{}),nativeCodex(dir,'plugin/installed',{}),nativeCodex(dir,'thread/goal/get',{threadId:d.nativeId})]);let skills:any[]=[];try{skills=await installedSkills(dir)}catch{}if(codexBackendMode==='app-server'&&!nativeControl.supportsPlan&&results[0].status==='fulfilled'){const modes=results[0].value;if(Array.isArray(modes.data))modes.data=modes.data.filter((m:any)=>m.mode!=='plan')}res.json({skills,mode:codexOptions.get(d.nativeId),...Object.fromEntries(['modes','plugins','goal'].map((key,i)=>[key,results[i].status==='fulfilled'?{data:(results[i] as PromiseFulfilledResult<any>).value}:{error:'当前 Codex 不支持或暂不可用'}]))});}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/local/:id/mode',async(req,res)=>{try{const d=await detailWithCreated(req.params.id);if(d.agent!=='Codex'||d.archived)throw Error('当前会话不可修改模式');if(!await desktopControlEnabled())throw Error('Codex 控制未启用');if(codexBackendMode==='app-server'&&req.body.mode==='plan'&&!nativeControl.supportsPlan)throw Error('当前终端后端尚未提供可验证的计划模式协议');const modes=await nativeCodex(dir,'collaborationMode/list',{});if(!modes.data?.some((m:any)=>m.mode===req.body.mode))throw Error('当前 Codex 未提供此模式');codexOptions.set(d.nativeId,req.body.mode);res.json({mode:req.body.mode})}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/local/:id/goal',async(req,res)=>{try{const d=await detailWithCreated(req.params.id);if(d.agent!=='Codex'||d.archived)throw Error('当前会话不可修改目标');if(!await desktopControlEnabled())throw Error('Codex 控制未启用');const op=goalParams(d.nativeId,req.body);res.json(await nativeCodex(dir,op.method,op.params))}catch(e){res.status(409).json({error:(e as Error).message})}});
app.get('/api/local/:id/resources',async(req,res)=>{try{const detail=await resourceDetail(req.params.id);const resources=(req.header('x-gcollie-media')==='references'?compactReferences:references)(detail);res.json({resources:await Promise.all(resources.map(async r=>{if(!/\/uploads\/[a-f0-9-]{36}\/content$/.test(r.ref))return r;try{const f=await resourceFile(detail,r.id);return {...r,name:f.name,image:f.image}}catch{return r}}))})}catch{res.status(404).json({error:'会话资源不可用'})}});
app.get('/api/local/:id/resources/:resource/poster',async(req,res)=>{try{const f=await resourceFile(await resourceDetail(req.params.id),req.params.resource);const path=await videoPoster(f);res.set('Cache-Control','private, max-age=300').type('image/jpeg').sendFile(path,{dotfiles:'allow'})}catch{res.status(404).json({error:'视频封面暂不可用，请重试'})}});
app.get('/api/local/:id/resources/:resource',async(req,res)=>{try{const f=await resourceFile(await resourceDetail(req.params.id),req.params.resource);res.set({'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});if(f.data)res.type(f.mime).send(f.data);else{if(f.mime)res.type(f.mime);res.sendFile(f.path,{dotfiles:'allow'})}}catch{res.status(404).json({error:'图片不存在或不允许访问'})}});
app.post('/api/local/:id/resources/:resource/preview',async(req,res)=>{try{res.json({path:await issuePreview(req.params.id,req.params.resource,attachmentDevice(res))})}catch{res.status(404).json({error:'文件已移动、删除或不允许预览'})}});
app.post('/api/attachments/media',async(req,res)=>{try{res.json(await attachments.addVideo(attachmentDevice(res),String(req.query.session||''),String(req.query.name||''),Number(req.headers['content-length']),req))}catch(e){if(!res.headersSent)res.status(400).json({error:(e as Error).message})}});
app.post('/api/attachments',(req,res)=>{try{res.json(attachments.add(attachmentDevice(res),req.body.session,req.body))}catch(e){res.status(400).json({error:(e as Error).message})}});
app.get('/api/attachments/:id',(req,res)=>{try{const a=attachments.content(req.params.id,attachmentDevice(res));res.set({'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; sandbox"});res.type(a.mime);if(!a.image)res.attachment(a.name);res.sendFile(a.path)}catch{res.sendStatus(404)}});
app.delete('/api/attachments/:id',(req,res)=>{try{attachments.remove(req.params.id,attachmentDevice(res));res.json({ok:true})}catch{res.sendStatus(404)}});
app.get('/api/devices',ownerOnly,(req,res)=>res.json({currentDeviceId:res.locals.device?.id,devices:auth.list(),inviteActive:auth.inviteActive()}));
app.post('/api/devices/pair/cancel',ownerOnly,(_req,res)=>{auth.cancelInvite();res.json({ok:true})});
app.post('/api/devices/pair',ownerOnly,async(req,res)=>{try{const invite=auth.challenge('control');const n=await currentNetwork();const raw=req.body.origin||n.tailscale.httpsURL||n.pairingAddresses[0]||`http://127.0.0.1:${port}`;const allowed=[n.tailscale.httpsURL,...n.pairingAddresses,`http://127.0.0.1:${port}`,`http://localhost:${port}`].filter(Boolean);if(!allowed.includes(raw))throw Error('请选择已检测到的访问地址');const url=raw+'/#pair='+encodeURIComponent(invite.secret);res.json({code:invite.code,expiresAt:invite.expiresAt,url,qr:await QRCode.toDataURL(url,{width:260,margin:2})})}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/devices/:id/revoke',ownerOnly,(req,res)=>{try{auth.revoke(String(req.params.id));notifications.unsubscribe(String(req.params.id));broadcast();res.json({ok:true})}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/auth/logout',(req,res)=>{if(res.locals.device){notifications.unsubscribe(res.locals.device.id);auth.logout(res.locals.device.id);}res.clearCookie('gcollie_device',{path:'/'});res.json({ok:true})});
app.post('/api/adapters/codex/control',ownerOnly,async(req,res)=>{try{if(typeof req.body.enabled!=='boolean')throw Error('无效设置');if(process.env.ORBIT_DESKTOP_CONTROL!==undefined)throw Error('当前由 ORBIT_DESKTOP_CONTROL 环境设置控制，请先修改服务配置');if(req.body.enabled&&!(await codexControlStatus()).available)throw Error('Codex 控制后端尚未连接，无法启用控制');const p=join(dir,'settings.json');await writeFile(p+'.tmp',JSON.stringify({codexControl:req.body.enabled}),{mode:0o600});await rename(p+'.tmp',p);res.json({enabled:await desktopControlEnabled()})}catch(e){res.status(409).json({error:(e as Error).message})}});
app.get('/api/diagnostics/system',ownerOnly,async(_req,res)=>{res.json({version:releasePackage.version,node:process.versions.node,platform:process.platform,host,uptimeSeconds:Math.round(process.uptime()),codex:{...await codexControlStatus(),controlEnabled:await desktopControlEnabled()},hermes:{discovery:'本机唯一后端',experimental:true},authentication:'per-device',notificationScope:'最近关注的 30 个会话，服务重启后恢复，断线期间不推断任务完成'})});
app.get('/api/folders',async(req,res)=>{try{if(res.locals.role==='view')throw Error('只读设备不能浏览电脑目录');res.json(await folderProjects.browse(typeof req.query.path==='string'?req.query.path:undefined))}catch(e){res.status(403).json({error:(e as Error).message})}});
app.post('/api/folders',async(req,res)=>{try{res.json(await folderProjects.createFolder(req.body.parent,req.body.name))}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/projects',async(req,res)=>{try{res.json(await folderProjects.add(req.body.path,req.body.name));broadcast()}catch(e){res.status(409).json({error:(e as Error).message})}});
app.get('/api/network',async(_req,res)=>res.json(await currentNetwork()));
app.get('/api/network/embedded',ownerOnly,(_req,res)=>res.json(embeddedNetwork.status()));
app.post('/api/network/embedded',ownerOnly,async(req,res)=>{try{let result;switch(req.body.action){case 'start':result=await embeddedNetwork.start();break;case 'login':result=embeddedNetwork.login();break;case 'logout':result=embeddedNetwork.logout();break;case 'stop':result=embeddedNetwork.stop();break;default:throw Error('未知网络操作')}res.json(result)}catch(e){res.status(409).json({error:(e as Error).message})}});
app.get('/api/notifications/feed',(req,res)=>{const after=req.query.after===undefined?undefined:Number(req.query.after);if(after!==undefined&&(!Number.isSafeInteger(after)||after<0)){res.status(400).json({error:'无效提醒游标'});return}res.json(notifications.feed(after))});
app.get('/api/push/key',(_req,res)=>res.json({publicKey:notifications.publicKey()}));
app.post('/api/push/subscribe',(req,res)=>{try{if(!res.locals.device)throw Error('请先登记本设备');notifications.subscribe(res.locals.device.id,req.body.subscription);res.json({ok:true})}catch(e){res.status(400).json({error:(e as Error).message})}});
app.post('/api/push/unsubscribe',(_req,res)=>{if(res.locals.device)notifications.unsubscribe(res.locals.device.id);res.json({ok:true})});
app.post('/api/push/test',async(_req,res)=>{const sent=res.locals.device?await notifications.test(res.locals.device.id):false;res.json({sent})});
app.get('/healthz',(_req,res)=>res.json({ok:true,version:releasePackage.version}));
const draftsPath=join(dir,'created-sessions.json');let created:Record<string,any>={};try{created=JSON.parse(await readFile(draftsPath,'utf8'))}catch{}
type ReadOptions={all?:boolean;before?:string};
function memoryHistory(detail:any,options:ReadOptions){
 return options.all||!options.before?detail:{...detail,...historyPage(detail.events||[],options.before)};
}
async function detailWithCreated(id:string,options:ReadOptions={}){
 try{return await detailLocal(id,options)}catch(e){
  if(!Object.hasOwn(created,id)||created[id].id!==id)throw e;
  return memoryHistory(created[id],options);
 }
}
async function sessionHistory(id:string,options:ReadOptions={}){
 if(id.startsWith('claude:'))return claude.detail(id.slice(7),options);
 if(id.startsWith('managed:')){
  const legacy=codex.get(id);
  if(!legacy.readOnly)return memoryHistory(legacy,options);
  id='codex:'+legacy.nativeId;
 }
 return detailWithCreated(id,options);
}
const sessionCreation=new SessionCreation(dir);
app.get('/api/sessions/requests/:requestId',(req,res)=>{
 res.setHeader('Cache-Control','no-store');
 try{res.json(sessionCreation.receipt(attachmentDevice(res),req.params.requestId))}
 catch(e){res.status(400).json({error:(e as Error).message})}
});
app.post('/api/sessions',async(req,res)=>{try{
 const b=req.body??{},device=attachmentDevice(res);
 const result=await sessionCreation.run(device,b.requestId,async()=>{
  let fields;
  try{
   if(!['Hermes','Codex','Claude Code'].includes(b.agent))throw Error('未知助手');
   const cwd=typeof b.cwd==='string'?b.cwd.trim():'';
   const project=cwd?[...(await listLocal()).projects,...await folderProjects.list()].find((p:any)=>p.path===cwd):undefined;
   if(cwd&&!project)throw Error('请选择已接入的项目目录');
   if(b.title!==undefined&&(typeof b.title!=='string'||b.title.length>100))throw Error('会话名称不能超过 100 字');
   const modern=typeof b.draftId==='string';
   if(modern&&b.draftId!=='draft:'+b.requestId)throw Error('无效新会话草稿');
   if(modern&&typeof b.prompt!=='string')throw Error('请输入首条消息');
   const files=modern?attachments.resolve(b.attachments,device,b.draftId):[];
   // The desktop create path uses a prompt string with local file references.
   const prompt=modern?attachmentInput(b.prompt,files.map(f=>({...f,image:false}))).map(i=>i.text).join('\n'):b.prompt;
   const title=typeof b.title==='string'&&b.title.trim()?b.title.trim():sessionTitle(b.prompt||files[0]?.name||'');
   fields={cwd,project,modern,files,prompt,title};
  }catch(e){throw createNotSubmitted(e,'session_create_validation')}
  const {cwd,project,modern,files,prompt,title}=fields;
  if(b.agent==='Claude Code'){
   const r=await claude.create(title,cwd||homedir(),modern?b.prompt:prompt,files);
   if(modern)attachments.rebind(b.attachments||[],device,b.draftId,r.id);
   broadcast();return r;
  }
  if(b.agent==='Codex'){
   if(!await desktopControlEnabled())throw createNotSubmitted(Error('Codex 控制尚未启用'),'session_create_control_disabled');
   let prepared, desktopPrompt, folderSelected;
   try{
    prepared=await prepareAgentMedia(modern?b.prompt:prompt,files);
    if(codexBackendMode==='desktop'){
     desktopPrompt=attachmentInput(prepared.text,prepared.files.map(f=>({...f,image:false})),64000).map(i=>i.text).join('\n');
     folderSelected=await folderProjects.contains(cwd);
    }
   }catch(e){
    if(e instanceof InvalidImageAttachment)throw new SessionCreateError(e.message,'failed','session_create_invalid_image',e.attachmentId);
    throw createNotSubmitted(e,'session_create_prepare');
   }
   const r=codexBackendMode==='app-server'
    ?await nativeControl.create({...b,title,prompt:prepared.text,attachments:prepared.files,mediaPrepared:true,cwd:cwd||homedir()})
    :await desktopCreator.create({...b,title,prompt:desktopPrompt,cwd,folderSelected});
   if(codexBackendMode==='app-server'){const id='codex:'+r.threadId;created[id]={id,nativeId:r.threadId,agent:'Codex',title,cwd:cwd||homedir(),project:project?.name||'无项目',projectPath:cwd||null,updatedAt:Date.now(),archived:false,events:[],historyLimit:200,readOnly:true};await writeFile(draftsPath,JSON.stringify(created),{mode:0o600});r.id=id;if(cwd&&await folderProjects.contains(cwd))await folderProjects.assign(r.threadId,cwd);}
   if(modern)attachments.rebind(b.attachments||[],device,b.draftId,r.id);
   invalidateLocal();broadcast();return r;
  }
  const workdir=cwd||homedir();
  const r=await hermes.create({...b,title:modern?undefined:title,cwd:workdir});
  const rows=await hermes.active(),row=rows.find((s:any)=>s.id===r.session_id);
  const nativeId=r.stored_session_id||row?.session_key;
  if(!nativeId)throw Error('会话已创建，等待 Hermes 返回持久标识，请刷新列表');
  const id='hermes:'+nativeId;
  if(cwd&&await folderProjects.contains(cwd))await folderProjects.assign(nativeId,cwd);
  created[id]={id,nativeId,agent:'Hermes',title,cwd:workdir,project:project?project.name:'无项目',projectPath:cwd||null,updatedAt:Date.now(),archived:false,events:[],historyLimit:200,readOnly:true};
  await writeFile(draftsPath,JSON.stringify(created),{mode:0o600});
  if(modern){attachments.rebind(b.attachments||[],device,b.draftId,id);await hermes.action(nativeId,{action:'send',text:b.prompt,attachments:files,requestId:b.requestId+'-first'})}
  broadcast();return{id};
 });res.json(result);
}catch(e){
 const failure=e instanceof SessionCreateError?e:new SessionCreateError((e as Error).message,'unknown');
 res.status(409).json({error:failure.message,code:failure.code,outcome:failure.outcome,attachmentId:failure.attachmentId});
}});

function shareLink(key:string){const ip=Object.values(networkInterfaces()).flat().find(n=>n?.family==='IPv4'&&!n.internal)?.address;return(process.env.ORBIT_PUBLIC_URL||embeddedNetwork.publicStatus().address||`http://${ip||'127.0.0.1'}:${port}`).replace(/\/$/,'')+'/share/'+key}
app.get('/api/share/:id',(req,res)=>{const r=shares.latest(req.params.id);res.json(r?{kind:'orbit',...r,url:shareLink(r.key)}:null)});
app.post('/api/share/:id',async(req,res)=>{try{const id=req.params.id,b=req.body;if(b.action==='revoke'){shares.revoke(id,b.key);res.json({ok:true});return}if(b.action!=='create')throw Error('未知分享操作');const detail=await detailLocal(id);if(!id.startsWith('hermes:')&&!id.startsWith('codex:'))throw Error('暂不支持此来源分享');const r=shares.create(id,detail,b.requestId);const ip=Object.values(networkInterfaces()).flat().find(n=>n?.family==='IPv4'&&!n.internal)?.address;const origin=process.env.ORBIT_PUBLIC_URL||embeddedNetwork.publicStatus().address||`http://${ip||'127.0.0.1'}:${port}`;res.json({kind:'orbit',...r,url:origin.replace(/\/$/,'')+'/share/'+r.key})}catch(e){res.status(409).json({error:(e as Error).message})}});
const activations=new SessionActivation();
app.get('/api/local/:id/delete-eligibility',async(req,res)=>{res.json(await sessionDeletion.eligibility(req.params.id,res.locals.role))});
app.post('/api/local/:id/delete',async(req,res)=>{try{const result=await sessionDeletion.remove(req.params.id,req.body.requestId,res.locals.role);for(const id of result.deletedIds||[req.params.id]){delete created[id];notifications.forget(id);shares.revokeSession(id)}await writeFile(draftsPath,JSON.stringify(created),{mode:0o600});invalidateLocal();broadcast();res.json(result)}catch(e){const failure=e instanceof DeleteFailure?e:new DeleteFailure('删除状态无法确认，请刷新后检查','delete_result_unknown','unknown');res.status(failure.outcome==='unknown'?503:409).json({error:failure.message,code:failure.code,outcome:failure.outcome})}});
app.post('/api/local/:id/activate',async(req,res)=>{try{const result=await activations.run(req.params.id,async()=>{const id=req.params.id;if(id.startsWith('claude:')){const d=await claude.detail(id.slice(7));if(!d.claudeLive)throw Error(d.desktopError);return d}let d;try{d=await detailLocal(id)}catch(e){if(!created[id])throw e;d=created[id]}assertActivatable(d);if(d.agent==='Hermes'){const key=await hermes.load(d.nativeId);hermesMisses.delete(key);const live=await hermes.view(key);const detail=key===d.nativeId?d:await detailLocal('hermes:'+key);return{...mergeHermesDetail(detail,live),connectionState:'connected'}}if(!await desktopControlEnabled())throw Error('Codex 控制尚未启用');if(codexBackendMode==='app-server'){await nativeControl.load(d.nativeId);return{...d,...nativeControl.view(d.nativeId),desktopControl:true,connectionState:'connected'}}try{await desktop.follow(d.nativeId)}catch{await desktopCreator.load(d.nativeId);let last:any;for(let i=0;i<12;i++){try{await desktop.follow(d.nativeId);last=null;break}catch(e){last=e;await new Promise(r=>setTimeout(r,250))}}if(last)throw Error('已请求桌面打开会话，但实时连接尚未建立，请稍后重试')}desktopMisses.delete(d.nativeId);return{...d,...desktop.view(d.nativeId),desktopControl:true,connectionState:'connected'}});res.json(result)}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/claude/:id',async(req,res)=>{try{const files=attachments.resolve(req.body.attachments,attachmentDevice(res),'claude:'+req.params.id);res.json(await claude.action(req.params.id,{...req.body,attachments:files}))}catch(e){res.status(409).json({error:(e as Error).message})}});
app.post('/api/hermes/:id',async(req,res)=>{try{if(req.body.action==='attach'){const view=await hermes.view(req.params.id);hermesMisses.delete(req.params.id);res.json(view)}else if(req.body.action==='rename'||req.body.action==='archive'){const r=await hermes.manage(req.params.id,req.body);invalidateLocal();res.json(r)}else res.json(await hermes.action(req.params.id,{...req.body,attachments:attachments.resolve(req.body.attachments,attachmentDevice(res),'hermes:'+req.params.id)}))}catch(e){const outcome=hermes.operationOutcome(req.params.id,req.body.requestId)==='unknown'?'unknown':'failed';res.status(409).json({code:outcome==='unknown'?'hermes_result_unknown':'hermes_conflict',outcome,error:(e as Error).message+(outcome==='unknown'?'；操作结果未知，请刷新核对，勿重复提交':'')})}});
app.post('/api/desktop/:id',async(req,res)=>{try{if(req.body.action==='attach'){await desktop.follow(req.params.id);res.json(desktop.view(req.params.id));return}if(!await desktopControlEnabled())throw Error('Codex 控制尚未启用');res.json(await desktop.action(req.params.id,{...req.body,mode:codexOptions.get(req.params.id),skills:await resolveSkills(dir,(req.body.attachments||[]).filter((id:any)=>typeof id==='string'&&id.startsWith('skill:')).map((id:string)=>id.slice(6))),attachments:attachments.resolve((req.body.attachments||[]).filter((id:any)=>typeof id!=='string'||!id.startsWith('skill:')),attachmentDevice(res),'codex:'+req.params.id)}))}catch(e){if(req.body.action==='send'){try{const snapshot=await Promise.race([usage.readAccount(true),new Promise<never>((_,reject)=>{const t=setTimeout(()=>reject(Error('额度补查超时')),1500);t.unref()})]);const windows=exhaustedCodexWindows(snapshot.codexAccount);if(windows.length){res.status(429).json({code:'codex_quota_exhausted',error:windows.some((w:any)=>w.windowMinutes===300)?'Codex 5 小时额度已用完':'Codex 每周额度已用完',windows});return}}catch{}}res.status(409).json({code:/执行状态尚未同步|未收到桌面快照/.test(String(e))?'desktop_not_synced':/超时|结果未知/.test(String(e))?'desktop_result_unknown':/已提交|不重复/.test(String(e))?'desktop_already_submitted':'desktop_conflict',error:(e as Error).message})}});
app.post('/api/control/:id',async(req,res)=>{try{res.json(await codex.action(req.params.id,req.body))}catch(e){res.status(409).json({error:(e as Error).message})}});
app.get('/api/local',async(_req,res)=>{try{const d=structuredClone(await listLocal());for(const p of await folderProjects.list()){if(!d.projects.some((v:any)=>v.path===p.path))d.projects.push(p)}const cs=(await claude.list()).map(({_path,...s}:any)=>s);d.sessions=[...cs,...d.sessions];for(const s of cs){if(!s.projectPath)continue;const p=d.projects.find((p:any)=>p.path===s.projectPath);if(p){if(!p.agents.includes('Claude Code'))p.agents.push('Claude Code')}else d.projects.push({path:s.projectPath,name:s.project,agents:['Claude Code'],sessions:cs.filter((v:any)=>v.projectPath===s.projectPath).length})}const managed=codex.list().filter(s=>!s.readOnly||!d.sessions.some((v:any)=>v.nativeId===s.nativeId));const ids=new Set(managed.map(s=>s.nativeId));res.json({...d,sessions:[...Object.values(created).filter((s:any)=>!d.sessions.some((v:any)=>v.id===s.id)),...managed,...d.sessions.filter((s:any)=>!ids.has(s.nativeId))].sort((a:any,b:any)=>b.updatedAt-a.updatedAt)})}catch{res.status(503).json({error:'本地会话读取失败'})}});
app.get('/api/local/:id/history',async(req,res)=>{try{const before=typeof req.query.before==='string'?req.query.before:undefined;const d=await sessionHistory(req.params.id,{before});res.json(req.header('x-gcollie-media')==='references'?compactDetail(d):d)}catch(e){res.status(400).json({error:(e as Error).message})}});
app.get('/api/local/:id',async(req,res)=>{const sendJson=res.json.bind(res);if(req.header('x-gcollie-media')==='references')res.json=(value:any)=>sendJson(compactDetail(value));try{const d=await sessionHistory(req.params.id),id=d.id;if(id.startsWith('claude:')||id.startsWith('managed:')){res.json(d);return}if(!d.archived)notifications.watch(id,d.title,async()=>{if(id.startsWith('hermes:'))return hermes.view(d.nativeId);return desktop.view(d.nativeId)});if(d.archived){res.json({...d,desktopLive:false,readOnly:true,connectionState:'archived',desktopError:'此会话已归档，请先在电脑取消归档后继续'});return}if(id.startsWith('hermes:')){if(Date.now()<(hermesMisses.get(d.nativeId)||0)){res.json({...d,connectionState:'notLoaded',desktopError:'历史会话尚未连接，点击重新连接'});return}try{const live=await hermes.view(d.nativeId);res.json(mergeHermesDetail(d,live));hermesMisses.delete(d.nativeId)}catch(e){hermesMisses.set(d.nativeId,Date.now()+10000);res.json({...d,desktopError:(e as Error).message})}return}if(!id.startsWith('codex:')){res.json(d);return}const enabled=await desktopControlEnabled();let desktopError:string|undefined;if(enabled&&(!desktopMisses.has(d.nativeId)||Date.now()>(desktopMisses.get(d.nativeId)||0))){try{await desktop.follow(d.nativeId);desktopMisses.delete(d.nativeId)}catch{desktopMisses.set(d.nativeId,Date.now()+15000);desktopError=codexBackendMode==='app-server'?'Codex 终端后端暂不可达，请重新连接':'桌面未加载此会话或暂时不可达，请在桌面打开该聊天后重试'}}const live=desktop.view(d.nativeId);if(codexBackendMode==='app-server'&&enabled&&!live.desktopLive&&!desktopError)desktopError='此会话尚未连接，点击重新连接';res.json({...d,...live,sendReceipts:desktop.receipts(d.nativeId),desktopControl:enabled,desktopError})}catch{res.status(404).json({error:'会话不存在或无法读取'})}});
app.get('/api/tasks',(_req,res)=>res.json({tasks,revision,serverTime:Date.now()}));
app.get('/api/events',(req,res)=>{res.setHeader('Content-Type','text/event-stream');res.setHeader('Connection','keep-alive');res.flushHeaders();clients.add(res);res.write(`event: refresh\ndata: {}\n\n`);const timer=setInterval(()=>{if(res.locals.device&&!auth.list().some(d=>d.id===res.locals.device.id)){res.end();return}res.write(': heartbeat\n\n')},15000);req.on('close',()=>{clearInterval(timer);clients.delete(res)})});
let mutation=Promise.resolve();
app.post('/api/tasks/:id/actions',(req,res)=>{mutation=mutation.then(async()=>{try{const {requestId,action,text,approvalId}=req.body;if(typeof requestId!=='string'||requestId.length>100)throw Error('缺少操作编号');const key=`${req.params.id}:${requestId}`;if(seen.has(key)){res.json({ok:true,duplicate:true});return}const task=tasks.find(t=>t.id===req.params.id);if(!task){res.status(404).json({error:'任务不存在'});return}applyAction(task,action,text,approvalId);await persist();seen.set(key,Date.now());if(seen.size>5000)seen.delete(seen.keys().next().value!);broadcast();res.json({ok:true})}catch(e){res.status(409).json({error:(e as Error).message})}})});
app.post('/api/demo/reset',(_req,res)=>{mutation=mutation.then(async()=>{tasks=seeds();await persist();broadcast();res.json({ok:true})})});
let observedAccountKey:string|null=null;
const accountLimits=async()=>{
 const raw=await readQuotaWithFallback(()=>desktopCreator.usageLimits(),()=>nativeCodex(dir,'account/rateLimits/read',{}));
 const accountKey=raw.accountId||raw.accountKey;
 if(accountKey){observedAccountKey=accountKey;return{...raw,accountKey,accountLabel:accountKey};}
 const {account}=await nativeCodex(dir,'account/read',{});
 observedAccountKey=account?.accountId||account?.email||null;return{...raw,accountKey:observedAccountKey};
};
const usage=new UsageService(dir,accountLimits,async()=>{const expected=observedAccountKey;if(!expected)throw Error('账号统计身份尚未同步');const value=await nativeCodex(dir,'account/usage/read',{},expected);if(expected!==observedAccountKey)throw Error('账号已变化');return value},()=>accountRevision(dir));
const resets=new ResetService(()=>codex.usageLimits(),p=>codex.consumeReset(p),()=>usage.invalidateAccount(),join(dir,'reset-attempt-cards.json'));
const schedules=new Schedules(join(dir,'schedules.json'),async task=>{
 if(!auth.list().some(d=>d.id===task.device))throw Error('来源设备已解除配对或授权过期');
 const {codexAccount:account}=await usage.readAccount();if(account.limitsError)throw Error('Codex 额度暂时不可读，请检查账号连接');if(exhaustedCodexWindows(account).length)throw Error('Codex 额度不足');
 const requestId='schedule-'+task.id+'-'+task.lastRun;
 if(task.session==='new'){await desktopCreator.create({agent:'Codex',title:sessionTitle(task.text),prompt:task.text,cwd:'',requestId});invalidateLocal();broadcast();return}
 const id=task.session.slice(6);const detail=await detailLocal(task.session);if(detail.archived)throw Error('会话已归档');
 if(!await desktopControlEnabled())throw Error('Codex 控制不可用');if(codexBackendMode==='app-server')await nativeControl.load(id);else await desktop.follow(id);const state=desktop.view(id);if(!['idle','completed','interrupted'].includes(state.status))throw Error('会话忙碌或状态未确认，本次未发送');
 await desktop.action(id,{action:'send',text:task.text,requestId});broadcast();
});

setInterval(()=>void schedules.tick().catch(e=>console.error('定时消息状态保存失败',e.message)),10000).unref();
app.get('/api/schedules',(_req,res)=>res.json({tasks:schedules.list(attachmentDevice(res))}));
app.post('/api/schedules',(req,res)=>{try{res.json(schedules.upsert(attachmentDevice(res),req.body))}catch(e){res.status(400).json({error:(e as Error).message})}});
app.post('/api/schedules/:id',(req,res)=>{try{res.json(schedules.upsert(attachmentDevice(res),req.body,req.params.id))}catch(e){res.status(400).json({error:(e as Error).message})}});
app.delete('/api/schedules/:id',(req,res)=>{try{schedules.remove(attachmentDevice(res),req.params.id);res.json({ok:true})}catch(e){res.status(400).json({error:(e as Error).message})}});
app.post('/api/schedules/:id/cancel',(req,res)=>{try{schedules.remove(attachmentDevice(res),req.params.id);res.json({ok:true})}catch(e){res.status(400).json({error:(e as Error).message})}});
app.get('/api/diagnostics',async(_req,res)=>{const checks:any[]=[{name:'电脑服务',status:'正常',detail:'健康请求已到达来源电脑服务'}];try{const {codexAccount:r}=await usage.readAccount();if(r.limitsError)throw Error(r.limitsErrorCode==='auth_expired'?'token_revoked':r.resetUnavailableReason);checks.push({name:'Codex 额度查询',status:'正常',detail:r.accountKey?'账号连接正常':'额度可读，账号标识未提供'})}catch(e){const authFailure=/401|token_revoked|invalidated oauth/i.test(String(e));checks.push({name:'Codex 额度查询',status:'异常',detail:authFailure?'额度查询认证失败；电脑连接正常，此结果不代表聊天登录失效，请重新检查额度':'额度查询失败；电脑服务已响应，聊天可用性需单独确认'})}try{await listLocal();checks.push({name:'会话索引',status:'正常',detail:'可读取本地会话索引'})}catch{checks.push({name:'会话索引',status:'异常',detail:'会话索引读取失败，请检查电脑服务日志'})}res.json({time:new Date().toISOString(),checks,requestMetrics:history.metrics(),usageMetrics:usage.metrics(),recent:diagnosticEvents.slice(-30)})});
app.post('/api/usage/codex/reset',async(req,res)=>{try{res.json(await resets.reset(req.body))}catch(e){res.status(409).json({error:(e as Error).message})}});
app.get('/api/usage/limits',async(req,res)=>{res.set('Cache-Control','no-store');try{res.json(await usage.readAccount(req.query.refresh==='1'))}catch{res.status(503).json({error:'账号额度暂时不可用'})}});
app.get('/api/usage',async(req,res)=>{res.set('Cache-Control','no-store');try{res.json(await usage.read(req.query.refresh==='1'))}catch{res.status(503).json({error:'用量索引暂时不可用，请稍后刷新'})}});
app.get('/api/adapters',async(_req,res)=>{try{const data=structuredClone(await listLocal());const cs=await claude.list();data.sessions.push(...cs.map(s=>({...s,readOnly:s.readOnly??false})));res.json(adapterSummaries(data.sessions,{role:res.locals.role,codexEnabled:await desktopControlEnabled(),codexLiveIds:data.sessions.filter((s:any)=>s.agent==='Codex'&&desktop.view(s.nativeId).desktopLive).map((s:any)=>s.nativeId),codexBackend:codexBackendMode,claudeInstalled:existsSync(process.env.GCOLLIE_CLAUDE_BIN||join(homedir(),'.local/bin/claude'))}));}catch{res.status(503).json({error:'读取适配器失败'})}});
if(process.env.NODE_ENV==='production')app.use(express.static('dist'));else {const {createServer:viteServer}=await import('vite');const vite=await viteServer({server:{middlewareMode:true},appType:'spa'});app.use(vite.middlewares)}
app.use((err:Error,_req:express.Request,res:express.Response,_next:express.NextFunction)=>res.status(400).json({error:err.message}));
app.listen(port,host,()=>console.log(`G-Collie listening on ${host}:${port}. 管理密钥保存在 .data/access-token；请勿分享给手机。`));
