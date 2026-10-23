import{randomUUID}from'node:crypto';
import {createWriteStream,openSync,readSync,closeSync} from 'node:fs';
import {Transform,type Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import{mkdirSync,writeFileSync,readFileSync,readdirSync,statSync,rmSync}from'node:fs';
import{join,resolve}from'node:path';
export type Attachment={id:string;name:string;mime:string;size:number;image:boolean;video?:boolean;path:string;device:string;session:string;createdAt:number};
const MAX=10*1024*1024,QUOTA=200*1024*1024;
export class AttachmentStore{
 private root:string;
 constructor(dir:string){this.root=join(dir,'uploads');mkdirSync(this.root,{recursive:true,mode:0o700})}
 private get(id:string){if(!/^[a-f0-9-]{36}$/.test(id))throw Error('附件标识无效');const value=JSON.parse(readFileSync(join(this.root,id,'meta.json'),'utf8')) as Attachment;if(value.path!==resolve(this.root,id,'content'))throw Error('附件记录无效');return value}
 private check(id:string,device:string,session?:string){const a=this.get(id);if(a.device!==device||session!==undefined&&a.session!==session)throw Error('此附件不属于当前设备或会话');return a}
 add(device:string,session:string,b:any){if(!/^(codex|hermes|claude|draft):[a-zA-Z0-9_-]+$/.test(session))throw Error('请先选择桌面会话');if(typeof b.name!=='string'||!b.name.trim()||b.name.length>160)throw Error('文件名无效');if(typeof b.data!=='string'||b.data.length>Math.ceil(MAX/3)*4||!b.data||b.data.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(b.data))throw Error('请选择不超过 10 MB 的文件');const data=Buffer.from(b.data,'base64');if(!data.length||data.length>MAX)throw Error('请选择不超过 10 MB 的文件');let used=0;for(const id of readdirSync(this.root)){try{const a=this.get(id);if(Date.now()-a.createdAt>7*86400000){rmSync(join(this.root,id),{recursive:true,force:true});continue}used+=a.size}catch{}}if(used+data.length>QUOTA)throw Error('附件空间已满，请先清理附件');const mime=data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))?'image/png':data[0]===255&&data[1]===216&&data[2]===255?'image/jpeg':data.subarray(0,6).toString().match(/^GIF8[79]a$/)?'image/gif':data.subarray(0,4).toString()==='RIFF'&&data.subarray(8,12).toString()==='WEBP'?'image/webp':'application/octet-stream';if(b.image&&mime==='application/octet-stream')throw Error('照片支持 PNG、JPEG、GIF 和 WebP；其他格式请作为文件上传');const id=randomUUID();mkdirSync(join(this.root,id),{mode:0o700});const path=resolve(this.root,id,'content');const a:Attachment={id,name:b.name.replace(/[\\/\x00-\x1f\x7f]/g,'_'),mime,size:data.length,image:!!b.image&&mime.startsWith('image/'),path,device,session,createdAt:Date.now()};writeFileSync(path,data,{mode:0o600,flag:'wx'});writeFileSync(join(this.root,id,'meta.json'),JSON.stringify(a),{mode:0o600,flag:'wx'});return this.public(a)}
 private reserved=0;
 async addVideo(device:string,session:string,name:string,length:number,stream:Readable){
  if(!/^(codex|hermes|claude|draft):[a-zA-Z0-9_-]+$/.test(session))throw Error('请选择会话');
  if(typeof name!=='string'||!name.trim()||name.length>160)throw Error('文件名无效');
  if(!Number.isSafeInteger(length)||length<=0||length>100*1024*1024)throw Error('视频大小不能超过 100 MB');
  let used=0;for(const id of readdirSync(this.root)){try{const a=this.get(id);if(Date.now()-a.createdAt>7*86400000){rmSync(join(this.root,id),{recursive:true,force:true});continue}used+=a.size}catch{}}
  if(used+this.reserved+length>QUOTA)throw Error('附件空间已满，请先清理附件');
  this.reserved+=length;const id=randomUUID(),folder=join(this.root,id),path=resolve(folder,'content');mkdirSync(folder,{mode:0o700});let count=0;
  try{
   await pipeline(stream,new Transform({transform(chunk,encoding,done){count+=chunk.length;if(count>length)return done(Error('上传大小不符'));done(null,chunk)}}),createWriteStream(path,{flags:'wx',mode:0o600}));
   if(count!==length)throw Error('视频上传不完整，请重新选择');
   const header=Buffer.alloc(32),fd=openSync(path,'r');try{readSync(fd,header,0,32,0)}finally{closeSync(fd)}
   const mime=header.subarray(4,8).toString()==='ftyp'?(header.subarray(8,12).toString()==='qt  '?'video/quicktime':'video/mp4'):header.subarray(0,4).equals(Buffer.from([0x1a,0x45,0xdf,0xa3]))?'video/webm':null;
   if(!mime)throw Error('视频支持 MP4、MOV 和 WebM，请选择正确视频文件');
   const a:Attachment={id,name:name.replace(/[\\/\x00-\x1f\x7f]/g,'_'),mime,size:count,image:false,video:true,path,device,session,createdAt:Date.now()};
   writeFileSync(join(folder,'meta.json'),JSON.stringify(a),{mode:0o600,flag:'wx'});return this.public(a);
  }catch(e){rmSync(folder,{recursive:true,force:true});throw e}finally{this.reserved-=length}
 }
 rebind(ids:string[],device:string,from:string,to:string){const files=this.resolve(ids,device,from);for(const a of files){a.session=to;writeFileSync(join(this.root,a.id,'meta.json'),JSON.stringify(a),{mode:0o600})}}
 public(a:Attachment){return{id:a.id,name:a.name,mime:a.mime,size:a.size,image:a.image,video:a.video===true}}
 content(id:string,device:string){return this.check(id,device)}
 remove(id:string,device:string){this.check(id,device);rmSync(join(this.root,id),{recursive:true,force:true})}
 resolve(ids:any,device:string,session:string){if(ids===undefined)return[];if(!Array.isArray(ids)||ids.length>5||new Set(ids).size!==ids.length)throw Error('每条消息最多 5 个不同附件');return ids.map(id=>{if(typeof id!=='string')throw Error('附件无效');const a=this.check(id,device,session);if(statSync(a.path).size!==a.size)throw Error('附件文件已变化');return a})}
}
export function attachmentInput(text:string,files:Attachment[]=[],max=4000){if(typeof text!=='string'||text.length>max||(!text.trim()&&!files.length))throw Error('请输入消息或添加附件');const input:any[]=[];const refs=files.filter(f=>!f.image).map(f=>JSON.stringify({name:f.name,path:f.path}));const body=[text.trim(),refs.length?'用户主动附加的文件（路径在电脑本机）：\n'+refs.join('\n'):''].filter(Boolean).join('\n\n');if(body)input.push({type:'text',text:body,text_elements:[]});for(const f of files.filter(f=>f.image))input.push({type:'localImage',path:f.path});return input}
