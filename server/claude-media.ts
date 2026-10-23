import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {existsSync} from 'node:fs';
import {readFile,mkdir,stat} from 'node:fs/promises';
import {join,dirname} from 'node:path';
import type {Attachment} from './attachments.js';
const exec=promisify(execFile);
const ffmpeg=()=>process.env.GCOLLIE_FFMPEG||(existsSync(join(process.cwd(),'.tools/ffmpeg/ffmpeg'))?join(process.cwd(),'.tools/ffmpeg/ffmpeg'):existsSync('/usr/lib/g-collie/ffmpeg')?'/usr/lib/g-collie/ffmpeg':'ffmpeg');
async function image(path:string){const data=await readFile(path);if(!data.length||data.length>5*1024*1024)throw Error('图片转换后仍超过 5 MB，请压缩后重试');return{type:'image',_path:path,source:{type:'base64',media_type:'image/jpeg',data:data.toString('base64')}}}
export async function claudeMediaInput(text:string,files:Attachment[]=[]){
 if(typeof text!=='string'||text.length>4000||(!text.trim()&&!files.length))throw Error('请输入消息或添加附件');
 const deadline=Date.now()+25000;
 const content:any[]=[];if(text.trim())content.push({type:'text',text:text.trim()});
 for(const file of files){
  if(!file.image&&!file.video){content.push({type:'text',text:`用户主动附加的文件：${JSON.stringify({name:file.name,path:file.path})}`});continue}
  const cache=join(dirname(file.path),'media');await mkdir(cache,{recursive:true,mode:0o700});
  const run=(args:string[])=>exec(ffmpeg(),['-hide_banner','-loglevel','error','-nostdin','-threads','1',...args],{timeout:Math.max(1,Math.min(10000,deadline-Date.now())),maxBuffer:1024*1024});
  if(file.image){
   const output=join(cache,'image.jpg');if(!existsSync(output))await run(['-i',file.path,'-frames:v','1','-vf','scale=2048:2048:force_original_aspect_ratio=decrease','-q:v','3','-y',output]);
   content.push({type:'text',text:`照片：${file.name}`},await image(output));
  }else{
   let duration=0;
   try{await exec(ffmpeg(),['-hide_banner','-nostdin','-i',file.path],{timeout:Math.max(1,Math.min(5000,deadline-Date.now())),maxBuffer:256000})}catch(e:any){const match=String(e.stderr||'').match(/Duration: (\d+):(\d+):(\d+(?:\.\d+)?)/);if(match)duration=Number(match[1])*3600+Number(match[2])*60+Number(match[3])}
   content.push({type:'text',text:`视频附件：[${file.name.replace(/[\[\]]/g,'')}](${encodeURI(file.path)})\n以下是视频画面的均匀抽样，不含音频。${duration?'时长 '+duration.toFixed(1)+' 秒。':'时长未知，抽取前 15 秒。'}原文件保留在 ${JSON.stringify(file.path)}。`});
   const count=duration?Math.min(6,Math.max(1,Math.ceil(duration))):6;
   for(let i=0;i<count;i++){
    const time=duration?Math.min(duration-.05,(i+.5)*duration/count):i*3;
    const output=join(cache,`frame-${i}.jpg`);
    try{if(!existsSync(output))await run(['-ss',Math.max(0,time).toFixed(3),'-i',file.path,'-frames:v','1','-vf','scale=960:960:force_original_aspect_ratio=decrease','-q:v','4','-y',output]);await stat(output)}catch{if(!duration&&i>0)break;throw Error('视频画面提取失败，请选择可正常播放的 MP4、MOV 或 WebM 视频')}
    content.push({type:'text',text:`视频画面 ${i+1} · ${Math.max(0,time).toFixed(1)} 秒`},await image(output));
   }
  }
 }
 return{type:'user',message:{role:'user',content}};
}

export async function prepareAgentMedia(text:string,files:Attachment[]=[]){
 if(typeof text!=='string'||text.length>4000||(!text.trim()&&!files.length))throw Error('请输入消息或添加附件');
 if(!files.some(f=>f.image||f.video))return{text,files};
 const input=await claudeMediaInput(text,files);
 const body=input.message.content.filter(p=>p.type==='text').map(p=>p.text).join('\n\n');
 const images:Attachment[]=input.message.content.filter(p=>p.type==='image').map((p,i)=>({...files[0],id:files[0].id+'-'+i,name:'画面-'+(i+1)+'.jpg',path:p._path,mime:'image/jpeg',size:Buffer.from(p.source.data,'base64').length,image:true,video:false}));
 return{text:body,files:images};
}
