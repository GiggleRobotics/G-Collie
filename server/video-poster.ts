import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {mkdir,stat} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {ffmpeg} from './claude-media.js';
const exec=promisify(execFile),pending=new Map<string,Promise<string>>();
let active=0;const waiting:Array<()=>void>=[];
export async function videoPoster(file:{path:string;extension:string;size:number;mtime:number}) {
 if(!['.mp4','.mov','.m4v','.webm'].includes(file.extension))throw Error('此资源不是视频');
 const key=createHash('sha256').update([file.path,file.size,file.mtime].join('\0')).digest('hex');
 const dir=resolve(process.env.GCOLLIE_DATA_DIR||'.data','video-posters'),output=join(dir,key+'.jpg');
 try{await stat(output);return output}catch{}
 if(pending.has(key))return pending.get(key)!;
 const task=(async()=>{
  if(active>=2)await new Promise<void>(r=>waiting.push(r));else active++;
  try{
   await mkdir(dir,{recursive:true,mode:0o700});
   await exec(ffmpeg(),['-hide_banner','-loglevel','error','-nostdin','-threads','1','-i',file.path,'-frames:v','1','-vf','scale=960:960:force_original_aspect_ratio=decrease','-q:v','4','-y',output],{timeout:15000,maxBuffer:256000});
   await stat(output);return output;
  }finally{const next=waiting.shift();if(next)next();else active--;}
 })();pending.set(key,task);try{return await task}finally{pending.delete(key)}
}
