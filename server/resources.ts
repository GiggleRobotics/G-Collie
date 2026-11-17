import {previewPage,pdfPreview} from './preview-page.js';
import {createHash,randomBytes} from 'node:crypto';
import {realpath,stat,readFile} from 'node:fs/promises';
import {resolve,basename,extname,dirname,relative} from 'node:path';
import type {Express} from 'express';
import mammoth from 'mammoth';
import {marked} from 'marked';
import sanitize from 'sanitize-html';
import {createRequire as resourceRequire} from 'node:module';
const resolvePackage=resourceRequire(import.meta.url);
const extensions=new Set(['.png','.jpg','.jpeg','.gif','.webp','.pdf','.docx','.doc','.md','.txt','.csv','.xlsx','.pptx','.zip','.mp4','.mov','.m4v','.webm']);
const images=new Set(['.png','.jpg','.jpeg','.gif','.webp']);
export type Resource={id:string;name:string;image:boolean;ref:string};
// Only references present in user/assistant messages become addressable resources.
export function references(d:any):Resource[]{
 const refs=new Set<string>();const media=new Set<string>();const names=new Map<string,string>();
 const add=(ref:string)=>{refs.delete(ref);refs.add(ref)};
 for(const e of d.events||[]){if(!['user','assistant'].includes(e.role))continue;
  for(const r of e.media||[])if(typeof r==='string'){add(r);media.add(r);}
  for(const m of String(e.text||'').matchAll(/^MEDIA:[ \t]*(.+)$/gm)){const r=m[1].trim().replace(/^"|"$/g,'');if(/\.(mp4|mov|m4v|webm)$/i.test(r))add(r)}
  for(const m of String(e.text||'').matchAll(/!?\[([^\]]*)\]\(\s*(<[^>]+>|[^\n]*?)\s*\)/g)){let r=m[2];if(r.startsWith('<'))r=r.slice(1,-1);else r=r.replace(/\s+"[^"]*"$/,'');add(r);if(/\.(mp4|mov|m4v|webm)$/i.test(m[1]))names.set(r,m[1]);}
 }
 return [...refs].filter(r=>(!/^https?:|^data:/i.test(r)&&(extensions.has(extname(r.split(/[?#]/)[0]).toLowerCase())||media.has(r)||/\/uploads\/[a-f0-9-]{36}\/content$/.test(r)))||/^data:image\/(png|jpeg|gif|webp);base64,/i.test(r)).map(ref=>({id:createHash('sha256').update(d.id+'\0'+ref).digest('hex').slice(0,32),ref,name:names.get(ref)||(ref.startsWith('data:')?'会话图片.png':basename(ref.replace(/^file:\/\//,''))),image:ref.startsWith('data:')||images.has(extname(ref).toLowerCase())}));
}
// Compact responses keep image bytes behind the existing session-scoped resource checks.
export function compactReferences(d:any){return references(d).map(r=>r.ref.startsWith('data:')?{...r,ref:'gcollie-resource:'+r.id}:r)}
export function compactDetail(d:any){if(!d?.id||!Array.isArray(d.events))return d;const refs=new Map(references(d).filter(r=>r.ref.startsWith('data:')).map(r=>[r.ref,'gcollie-resource:'+r.id]));return{...d,events:d.events.map((e:any)=>({...e,media:(e.media||[]).map((ref:string)=>refs.get(ref)||ref)}))}}
export async function resourceFile(d:any,id:string){
 const r=references(d).find(r=>r.id===id);if(!r)throw Error('文件未被此会话引用');
 if(r.ref.startsWith('data:')){const m=r.ref.match(/^data:(image\/(?:png|jpeg|gif|webp));base64,([A-Za-z0-9+/=]+)$/);if(!m||m[2].length>8*1024*1024)throw Error('图片格式或大小不支持');const data=Buffer.from(m[2],'base64');return {...r,path:'',data,mime:m[1],size:data.length,mtime:0,extension:'.png'};}
 let ref=decodeURIComponent(r.ref).replace(/^sandbox:/,'');if(ref.startsWith('file:'))ref=new URL(ref).pathname;
 if(/^[a-z][a-z0-9+.-]*:/i.test(ref)||ref.includes('\0'))throw Error('不支持此文件地址');
 const path=await realpath(resolve(d.cwd||'.',ref));
 // Block credentials and hidden configuration even when a generated link points at them.
 const uploads=resolve(process.env.GCOLLIE_DATA_DIR||resolve('.data'),'uploads');const storedAttachment=path.startsWith(uploads+'/')&&/\/uploads\/[a-f0-9-]{36}\/(content|media\/(image|frame-\d+)\.jpg)$/.test(path);
 if((!storedAttachment&&path.split('/').some(p=>p.startsWith('.')&&!['.codex','.hermes'].includes(p)))||/(^|\/)(access-token|credentials|auth|settings|secrets)(\.|\/|$)/i.test(path)||(!storedAttachment&&!extensions.has(extname(path).toLowerCase())))throw Error('此文件不允许预览');
 if(storedAttachment){const derived=/\/media\/(image|frame-\d+)\.jpg$/.test(path);const meta=JSON.parse(await readFile(derived?resolve(path,'..','..','meta.json'):resolve(path,'..','meta.json'),'utf8'));if(meta.session!==d.id||(derived&&!meta.image&&!meta.video))throw Error('附件不属于此会话');const extension=derived?'.jpg':extname(meta.name).toLowerCase();if(!extensions.has(extension))throw Error('附件格式不支持');const st=await stat(path);if(!st.isFile()||st.size>(derived?5:100)*1024*1024||(!derived&&st.size!==meta.size))throw Error('附件文件已变化');const image=derived||meta.image===true;return {...r,name:meta.name,image,path,data:undefined as Buffer|undefined,mime:derived?'image/jpeg':meta.mime,size:st.size,mtime:st.mtimeMs,extension};}
 const st=await stat(path);if(!st.isFile()||st.size>(['.mp4','.mov','.m4v','.webm'].includes(extname(path).toLowerCase())?100:50)*1024*1024)throw Error('文件不存在或超过 50 MB');
 return {...r,path,data:undefined as Buffer|undefined,mime:'',size:st.size,mtime:st.mtimeMs,extension:extname(path).toLowerCase()};
}
async function markdownImage(document:string,ref:string,session:string){
 const decoded=decodeURIComponent(ref);if(/^[a-z][a-z0-9+.-]*:|^[/\\]|\0/i.test(decoded)||!images.has(extname(decoded).toLowerCase()))throw Error('图片地址不受支持');
 const root=await realpath(dirname(document)),path=await realpath(resolve(root,decoded));const child=relative(root,path);if(child.startsWith('..')||resolve(root,child)!==path)throw Error('图片超出文档目录');
 const d={id:session,cwd:root,events:[{role:'assistant',media:[path]}]};return resourceFile(d,references(d)[0].id);
}
const esc=(s:string)=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const safe=(s:string)=>sanitize(s,{allowedTags:sanitize.defaults.allowedTags.concat(['img','h1','h2']),allowedAttributes:{a:['href'],img:['src','alt'],td:['colspan','rowspan'],th:['colspan','rowspan']},allowedSchemes:['http','https','data'],allowedSchemesByTag:{img:['data']},allowProtocolRelative:false});
const page=previewPage;
export function installPreviews(app:Express,read:(id:string)=>Promise<any>,authorized:(device:string)=>boolean){
 const tickets=new Map<string,{session:string;resource:string;device:string;expires:number;assets?:Map<string,string>}>();
 const issue=async(session:string,resource:string,device:string)=>{await resourceFile(await read(session),resource);for(const[k,t]of tickets)if(t.expires<Date.now())tickets.delete(k);if(tickets.size>=500)tickets.delete(tickets.keys().next().value!);const key=randomBytes(24).toString('hex');tickets.set(key,{session,resource,device,expires:Date.now()+20*60*1000});return `/preview/${key}/view`;};
 app.get('/preview-assets/:name',async(req,res)=>{const names:Record<string,string>={'pdf.mjs':'pdfjs-dist/legacy/build/pdf.mjs','pdf.worker.mjs':'pdfjs-dist/legacy/build/pdf.worker.mjs'};const name=names[req.params.name];if(!name){res.sendStatus(404);return}let path=resolve('preview-assets',req.params.name);try{await stat(path)}catch{path=resolvePackage.resolve(name)}res.type('text/javascript').sendFile(path);});
 app.get('/preview/:key/:action',async(req,res)=>{try{
  const t=tickets.get(req.params.key);if(!t||t.expires<Date.now()||!authorized(t.device)){res.status(410).type('html').send(page('预览已过期','请返回 G-Collie，重新点击文件。'));return}
  const file=await resourceFile(await read(t.session),t.resource);
  res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','X-Robots-Tag':'noindex, nofollow','Content-Security-Policy':"default-src 'none'; script-src 'self' 'unsafe-inline'; worker-src 'self'; connect-src 'self'; media-src 'self'; img-src 'self' data:; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"});
  if(req.params.action==='asset'){
   const ref=t.assets?.get(String(req.query.id||''));if(!ref||file.extension!=='.md'){res.sendStatus(404);return}
   const asset=await markdownImage(file.path,ref,t.session);res.type(asset.extension).sendFile(asset.path,{dotfiles:'allow'});return;
  }
  if(req.params.action==='content'){if(req.query.download==='1')res.attachment(file.name);else res.set('Content-Disposition',`inline; filename*=UTF-8''${encodeURIComponent(file.name)}`);if(file.data)res.type(file.mime).send(file.data);else{if(file.mime)res.type(file.mime);res.sendFile(file.path,{dotfiles:'allow'})}return}
  if(req.params.action!=='view'){res.sendStatus(404);return}
  let body='';
  if(file.image)body='<img src="./content" alt="图片">';
  else if(['.mp4','.mov','.m4v','.webm'].includes(file.extension))body='<video controls playsinline preload="metadata" src="./content" style="width:100%;max-height:75vh;background:#111;border-radius:12px"></video>';
  else if(file.extension==='.pdf')body=pdfPreview();
  else if(file.extension==='.docx'){if(file.size>15*1024*1024)throw Error('Word 预览最大支持 15 MB');const r=await mammoth.convertToHtml({buffer:await readFile(file.path)},{externalFileAccess:false});body='<div class="notice">阅读模式 · 原文件排版可下载查看</div>'+safe(r.value);}
  else if(['.md','.txt','.csv'].includes(file.extension)){if(file.size>2*1024*1024)throw Error('文本预览最大支持 2 MB');const text=await readFile(file.path,'utf8');if(file.extension==='.md'){
    const tokens=marked.lexer(text),refs=new Set<string>();marked.walkTokens(tokens,token=>{if(token.type==='image')refs.add(token.href)});
    const assets=new Map<string,string>(),urls=new Map<string,string>();
    for(const ref of refs){if(/^data:image\/(png|jpeg|gif|webp);base64,/i.test(ref)){urls.set(decodeURIComponent(ref),ref);continue}try{await markdownImage(file.path,ref,t.session);const id=createHash('sha256').update(ref).digest('hex').slice(0,32);assets.set(id,ref);urls.set(decodeURIComponent(ref),'./asset?id='+id)}catch{}}
    t.assets=assets;
    body=sanitize(await marked.parser(tokens),{allowedTags:sanitize.defaults.allowedTags.concat(['img','h1','h2']),allowedAttributes:{a:['href'],img:['src','alt','loading'],td:['colspan','rowspan'],th:['colspan','rowspan']},allowedSchemes:['http','https','data'],allowedSchemesByTag:{img:['data']},allowProtocolRelative:false,transformTags:{img:(_tag,attrs):sanitize.Tag=>{let ref=attrs.src;try{ref=decodeURIComponent(ref)}catch{}return urls.has(ref)?{tagName:'img',attribs:{src:urls.get(ref)!,alt:attrs.alt||'文档图片',loading:'eager'}}:{tagName:'span',attribs:{},text:'图片不可用（文件缺失或无权访问）'+(attrs.alt?'：'+attrs.alt:'')}}}});
    body+=`<script>(()=>{for(const image of document.querySelectorAll('main img')){const failed=()=>{const note=document.createElement('span');note.textContent='图片加载失败，请检查电脑连接后返回重试。';image.replaceWith(note)};image.addEventListener('error',failed,{once:true});if(image.complete&&image.naturalWidth===0)failed()}})()</script>`;
   }else body=`<pre>${esc(text)}</pre>`;}
  else body='<p>此格式请下载后使用手机上的应用打开。</p>';
  if(['.mp4','.mov','.m4v','.webm'].includes(file.extension)){
   res.type('html').send(`<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}video{display:block;width:100%;height:100%;object-fit:contain}p{color:white;font:14px sans-serif;position:absolute;top:40%;width:100%;text-align:center}</style><video controls ${req.query.autoplay==='1'?'autoplay':''} playsinline preload="metadata" src="./content" onerror="document.querySelector('p').hidden=false"></video><p hidden>视频加载失败或格式暂不支持，请返回重试。</p></html>`);return;
  }
  res.type('html').send(page(file.name,body,req.query.embedded==='1',file.extension==='.pdf'));
 }catch{res.status(404).type('html').send(page('文件暂时无法预览','文件可能已移动、删除、格式不受支持或超过预览大小限制。请返回 App 重试，或联系电脑端检查文件。'));}});
 return issue;
}
