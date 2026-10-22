import {previewPage,pdfPreview} from './preview-page.js';
import {createHash,randomBytes} from 'node:crypto';
import {realpath,stat,readFile} from 'node:fs/promises';
import {resolve,basename,extname} from 'node:path';
import type {Express} from 'express';
import mammoth from 'mammoth';
import {marked} from 'marked';
import sanitize from 'sanitize-html';
import {createRequire as resourceRequire} from 'node:module';
const resolvePackage=resourceRequire(import.meta.url);
const extensions=new Set(['.png','.jpg','.jpeg','.gif','.webp','.pdf','.docx','.doc','.md','.txt','.csv','.xlsx','.pptx','.zip']);
const images=new Set(['.png','.jpg','.jpeg','.gif','.webp']);
export type Resource={id:string;name:string;image:boolean;ref:string};
// Only references present in user/assistant messages become addressable resources.
export function references(d:any):Resource[]{
 const refs=new Set<string>();const media=new Set<string>();
 for(const e of d.events||[]){if(!['user','assistant'].includes(e.role))continue;
  for(const r of e.media||[])if(typeof r==='string'){refs.add(r);media.add(r);}
  for(const m of String(e.text||'').matchAll(/!?\[[^\]]*\]\(\s*(<[^>]+>|[^\n]*?)\s*\)/g)){let r=m[1];if(r.startsWith('<'))r=r.slice(1,-1);else r=r.replace(/\s+"[^"]*"$/,'');refs.add(r);}
 }
 return [...refs].filter(r=>(!/^https?:|^data:/i.test(r)&&(extensions.has(extname(r.split(/[?#]/)[0]).toLowerCase())||media.has(r)))||/^data:image\/(png|jpeg|gif|webp);base64,/i.test(r)).map(ref=>({id:createHash('sha256').update(d.id+'\0'+ref).digest('hex').slice(0,32),ref,name:ref.startsWith('data:')?'会话图片.png':basename(ref.replace(/^file:\/\//,'')),image:media.has(ref)||ref.startsWith('data:')||images.has(extname(ref).toLowerCase())}));
}
export async function resourceFile(d:any,id:string){
 const r=references(d).find(r=>r.id===id);if(!r)throw Error('文件未被此会话引用');
 if(r.ref.startsWith('data:')){const m=r.ref.match(/^data:(image\/(?:png|jpeg|gif|webp));base64,([A-Za-z0-9+/=]+)$/);if(!m||m[2].length>8*1024*1024)throw Error('图片格式或大小不支持');const data=Buffer.from(m[2],'base64');return {...r,path:'',data,mime:m[1],size:data.length,mtime:0,extension:'.png'};}
 let ref=decodeURIComponent(r.ref).replace(/^sandbox:/,'');if(ref.startsWith('file:'))ref=new URL(ref).pathname;
 if(/^[a-z][a-z0-9+.-]*:/i.test(ref)||ref.includes('\0'))throw Error('不支持此文件地址');
 const path=await realpath(resolve(d.cwd||'.',ref));
 // Block credentials and hidden configuration even when a generated link points at them.
 const uploads=resolve(process.env.GCOLLIE_DATA_DIR||resolve('.data'),'uploads');const storedImage=r.image&&path.startsWith(uploads+'/')&&/\/uploads\/[a-f0-9-]{36}\/content$/.test(path);
 if((!storedImage&&path.split('/').some(p=>p.startsWith('.')&&!['.codex','.hermes'].includes(p)))||/(^|\/)(access-token|credentials|auth|settings|secrets)(\.|\/|$)/i.test(path)||(!storedImage&&!extensions.has(extname(path).toLowerCase())))throw Error('此文件不允许预览');
 if(storedImage){const meta=JSON.parse(await readFile(resolve(path,'..','meta.json'),'utf8'));if(meta.session!==d.id||!meta.image)throw Error('附件不属于此会话');const data=await readFile(path);return {...r,name:meta.name,path:'',data,mime:meta.mime,size:data.length,mtime:0,extension:'.png'};}
 const st=await stat(path);if(!st.isFile()||st.size>50*1024*1024)throw Error('文件不存在或超过 50 MB');
 return {...r,path,data:undefined as Buffer|undefined,mime:'',size:st.size,mtime:st.mtimeMs,extension:extname(path).toLowerCase()};
}
const esc=(s:string)=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const safe=(s:string)=>sanitize(s,{allowedTags:sanitize.defaults.allowedTags.concat(['img','h1','h2']),allowedAttributes:{a:['href'],img:['src','alt'],td:['colspan','rowspan'],th:['colspan','rowspan']},allowedSchemes:['http','https','data'],allowedSchemesByTag:{img:['data']},allowProtocolRelative:false});
const page=previewPage;
export function installPreviews(app:Express,read:(id:string)=>Promise<any>,authorized:(device:string)=>boolean){
 const tickets=new Map<string,{session:string;resource:string;device:string;expires:number}>();
 const issue=async(session:string,resource:string,device:string)=>{await resourceFile(await read(session),resource);for(const[k,t]of tickets)if(t.expires<Date.now())tickets.delete(k);if(tickets.size>=500)tickets.delete(tickets.keys().next().value!);const key=randomBytes(24).toString('hex');tickets.set(key,{session,resource,device,expires:Date.now()+20*60*1000});return `/preview/${key}/view`;};
 app.get('/preview-assets/:name',async(req,res)=>{const names:Record<string,string>={'pdf.mjs':'pdfjs-dist/legacy/build/pdf.mjs','pdf.worker.mjs':'pdfjs-dist/legacy/build/pdf.worker.mjs'};const name=names[req.params.name];if(!name){res.sendStatus(404);return}let path=resolve('preview-assets',req.params.name);try{await stat(path)}catch{path=resolvePackage.resolve(name)}res.type('text/javascript').sendFile(path);});
 app.get('/preview/:key/:action',async(req,res)=>{try{
  const t=tickets.get(req.params.key);if(!t||t.expires<Date.now()||!authorized(t.device)){res.status(410).type('html').send(page('预览已过期','请返回 G-Collie，重新点击文件。'));return}
  const file=await resourceFile(await read(t.session),t.resource);
  res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','X-Robots-Tag':'noindex, nofollow','Content-Security-Policy':"default-src 'none'; script-src 'self' 'unsafe-inline'; worker-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"});
  if(req.params.action==='content'){if(req.query.download==='1')res.attachment(file.name);else res.set('Content-Disposition',`inline; filename*=UTF-8''${encodeURIComponent(file.name)}`);if(file.data)res.type(file.mime).send(file.data);else res.sendFile(file.path);return}
  if(req.params.action!=='view'){res.sendStatus(404);return}
  let body='';
  if(file.image)body='<img src="./content" alt="图片">';
  else if(file.extension==='.pdf')body=pdfPreview();
  else if(file.extension==='.docx'){if(file.size>15*1024*1024)throw Error('Word 预览最大支持 15 MB');const r=await mammoth.convertToHtml({buffer:await readFile(file.path)},{externalFileAccess:false});body='<div class="notice">阅读模式 · 原文件排版可下载查看</div>'+safe(r.value);}
  else if(['.md','.txt','.csv'].includes(file.extension)){if(file.size>2*1024*1024)throw Error('文本预览最大支持 2 MB');const text=await readFile(file.path,'utf8');body=file.extension==='.md'?safe(await marked(text)):`<pre>${esc(text)}</pre>`;}
  else body='<p>此格式请下载后使用手机上的应用打开。</p>';
  res.type('html').send(page(file.name,body,req.query.embedded==='1',file.extension==='.pdf'));
 }catch{res.status(404).type('html').send(page('文件暂时无法预览','文件可能已移动、删除、格式不受支持或超过预览大小限制。请返回 App 重试，或联系电脑端检查文件。'));}});
 return issue;
}
