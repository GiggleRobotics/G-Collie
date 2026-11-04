import MediaBrowser from './MediaBrowser';
import React,{useEffect,useState,useRef} from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
type Resource={id:string;ref:string;name:string;image:boolean};
const MediaContext=React.createContext<((id:string)=>void)|null>(null);
type Api=(path:string,body?:any)=>Promise<any>;
const video=(s:string)=>/\.(mp4|mov|m4v|webm)(?:[?#].*)?$/i.test(s);
function ImagePreview({src,alt,thumbnail=false}:{src:string;alt:string;thumbnail?:boolean}){
 const open=React.useContext(MediaContext);const dialog=useRef<HTMLDialogElement>(null);const[zoom,setZoom]=useState(1);
 if(thumbnail)return <img src={src} alt={alt} loading="lazy"/>;
 return <><button className="session-image-open" aria-label={'查看图片：'+alt} onClick={()=>{if(open){open('remote:'+src);return}setZoom(1);dialog.current?.showModal()}}><img className="session-media" src={src} alt={alt} loading="lazy"/></button><dialog ref={dialog} className="session-image-dialog" onClick={e=>{if(e.target===e.currentTarget)dialog.current?.close()}}><header><span>{alt}</span><button aria-label="缩小图片" disabled={zoom<=1} onClick={()=>setZoom(Math.max(1,zoom-0.5))}>−</button><button aria-label="放大图片" disabled={zoom>=4} onClick={()=>setZoom(Math.min(4,zoom+0.5))}>＋</button><button aria-label="关闭图片预览" onClick={()=>dialog.current?.close()}>×</button></header><div className="session-image-viewport"><img src={src} alt={alt} style={{width:zoom===1?'auto':zoom*100+'%',maxWidth:zoom===1?'100%':'none',maxHeight:zoom===1?'100%':'none'}}/></div></dialog></>;
}
function LocalMedia({resource,root,api,thumbnail=false}:{resource:Resource;root:string;api:Api;thumbnail?:boolean}){
 const open=React.useContext(MediaContext);
 const[url,setUrl]=useState(''),[error,setError]=useState('');
 const isVideo=video(resource.ref)||video(resource.name);
 useEffect(()=>{let live=true;setUrl('');setError('');api(root+'/'+resource.id+'/preview',{}).then(r=>{if(live)setUrl(new URL('./content',new URL(r.path,location.origin)).toString())}).catch(()=>{if(live)setError('媒体暂时无法加载，请检查文件和连接')});return()=>{live=false}},[root,resource.id,api]);
 if(error)return <p role="status">{error}</p>;
 if(!url)return <p className="muted">正在加载媒体…</p>;
 return isVideo&&thumbnail?<img className="session-media" alt={resource.name} src={'/api'+root+'/'+resource.id+'/poster'}/>:isVideo?<><video className="session-media" controls playsInline preload="metadata" src={url} poster={'/api'+root+'/'+resource.id+'/poster'}/><button className="text-button" onClick={()=>open?.(resource.id)}>浏览会话媒体</button></>:thumbnail?<ImagePreview src={url} alt={resource.name} thumbnail/>:<button className="session-image-open" aria-label={'查看图片：'+resource.name} onClick={()=>open?.(resource.id)}><img className="session-media" src={url} alt={resource.name} loading="lazy"/></button>;
}
function ImageGallery({images,root,api}:{images:Resource[];root:string;api:Api}){
 const[selected,setSelected]=useState('');
 const current=images.find(r=>r.id===selected)||images[0];
 if(!current)return null;
 if(images.length===1)return <LocalMedia resource={current} root={root} api={api}/>;
 return <div className="session-image-gallery"><div className="session-image-main"><LocalMedia resource={current} root={root} api={api}/></div><div className="session-image-thumbnails" aria-label="会话图片">{images.map((r,i)=><button key={r.id} aria-label={'选择第 '+(i+1)+' 张图片'} aria-pressed={current.id===r.id} onClick={()=>setSelected(r.id)}><LocalMedia resource={r} root={root} api={api} thumbnail/></button>)}</div></div>;
}
export default function SessionMedia({session,event,api,events=[]}:{session:string;event:any;api:Api;events?:any[]}){
 const[preview,setPreview]=useState('');
 const[resources,setResources]=useState<Resource[]>([]);
 const root='/local/'+encodeURIComponent(session)+'/resources';
 useEffect(()=>{let live=true;api(root).then(r=>{if(live)setResources(r.resources||[])}).catch(()=>{});return()=>{live=false}},[root,api]);
 const text=String(event.text||'');
 const ownRefs=new Set<string>(event.media||[]);for(const m of text.matchAll(/!?\[[^\]]*\]\(\s*(<[^>]+>|[^\n]*?)\s*\)/g))ownRefs.add(m[1].replace(/^<|>$/g,'').replace(/\s+"[^"]*"$/,''));
 const referenced=resources.filter(r=>ownRefs.has(r.ref));
 const local=(src:string|undefined)=>resources.find(r=>r.ref===src);
 const textOnly=text.replace(/^MEDIA:[ \t]*(.+)$/gm,(line,ref)=>referenced.some(r=>r.ref===ref.trim())?'':line);
 const remote=new Map<string,any>();for(const e of events){if(!['user','assistant'].includes(e.role))continue;for(const m of String(e.text||'').matchAll(/(!?)\[[^\]]*\]\((https?:[^\s)]+)\)/g)){const ref=m[2];if(m[1]||video(ref))remote.set('remote:'+ref,{id:'remote:'+ref,ref,name:video(ref)?'会话视频':'会话图片',image:!video(ref),remote:ref})}}for(const ref of event.media||[]){if(/^https?:/.test(ref))remote.set('remote:'+ref,{id:'remote:'+ref,ref,name:'会话媒体',image:!video(ref),remote:ref})}
 const allMedia=[...resources.filter(r=>r.image||video(r.ref)||video(r.name)),...remote.values()];
 return <MediaContext.Provider value={setPreview}><Markdown remarkPlugins={[remarkGfm]} components={{img:({src,alt})=>{const r=local(src);return r?null:src&&/^https?:/i.test(src)?<ImagePreview src={src} alt={alt||'图片'}/>:<span>{alt||'图片正在加载…'}</span>},a:({href,children})=>{const r=local(href);return r&&(r.image||video(r.ref)||video(r.name))?null:href&&video(href)&&/^https?:/i.test(href)?<video className="session-media" controls playsInline preload="metadata" src={href}/>:<a href={href}>{children}</a>}}}>{textOnly}</Markdown>{<ImageGallery images={referenced.filter(r=>r.image||video(r.ref)||video(r.name))} root={root} api={api}/>}{preview&&allMedia.some(r=>r.id===preview)&&<MediaBrowser key={session} items={allMedia} initial={preview} root={root} api={api} onClose={()=>setPreview('')}/>}</MediaContext.Provider>;
}
