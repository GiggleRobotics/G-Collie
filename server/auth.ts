import{createHash,randomBytes,randomInt,timingSafeEqual}from'node:crypto';
import{readFileSync,writeFileSync,renameSync}from'node:fs';import{join}from'node:path';
export type Device={id:string;name:string;role:'owner'|'control'|'view';createdAt:number;lastSeenAt:number;expiresAt:number;hash:string};
const digest=(v:string)=>createHash('sha256').update(v).digest('hex');
export class DeviceAuth{
 private devices:Device[]=[];private invite?:{code:string;secret:string;expiresAt:number;attempts:number;role:'control'|'view'};
 constructor(private root:string,private now=Date.now){try{const d=JSON.parse(readFileSync(join(root,'devices.json'),'utf8'));if(!Array.isArray(d))throw Error('设备登记损坏');this.devices=d.map((v:Device)=>({...v,role:v.role==='view'?'control':v.role}));}catch(e:any){if(e.code!=='ENOENT')throw Error('设备登记无法读取，拒绝启动；请检查 devices.json')}}
 private save(){const p=join(this.root,'devices.json');writeFileSync(p+'.tmp',JSON.stringify(this.devices),{mode:0o600});renameSync(p+'.tmp',p)}
 enroll(name:string,role:Device['role']){const token=randomBytes(32).toString('base64url'),now=this.now();this.devices=this.devices.filter(d=>d.expiresAt>now);if(this.devices.length>=100)throw Error('已达到 100 台设备上限，请先撤销旧设备');const device:Device={id:crypto.randomUUID(),name:String(name||'未命名设备').trim().slice(0,80),role,createdAt:now,lastSeenAt:now,expiresAt:now+90*86400000,hash:digest(token)};this.devices.push(device);this.save();return{token,device:this.public(device)}}
 authenticate(token:string){if(!token||token.length>256)return;const hash=digest(token);const d=this.devices.find(d=>d.hash===hash&&d.expiresAt>this.now());if(d&&this.now()-d.lastSeenAt>60000){d.lastSeenAt=this.now();this.save()}return d}
 public(d:Device){const{hash,...safe}=d;return safe}
 cancelInvite(){this.invite=undefined}
 inviteActive(){return !!this.invite&&this.invite.expiresAt>this.now()}
 list(){return this.devices.filter(d=>d.expiresAt>this.now()).map(d=>this.public(d))}
 revoke(id:string){const d=this.devices.find(d=>d.id===id);if(!d)throw Error('设备不存在');if(d.role==='owner'&&this.devices.filter(v=>v.role==='owner'&&v.expiresAt>this.now()).length<=1)throw Error('请先在电脑建立另一个管理端，不能撤销最后一个管理设备');this.devices=this.devices.filter(d=>d.id!==id);this.save()}
 logout(id:string){this.devices=this.devices.filter(d=>d.id!==id);this.save()}
 challenge(role:'control'|'view'='control'){if(!['control','view'].includes(role))throw Error('无效设备权限');const code=String(randomInt(0,1000000)).padStart(6,'0'),secret=randomBytes(24).toString('base64url'),expiresAt=this.now()+10*60000;this.invite={code:digest(code),secret:digest(secret),expiresAt,attempts:0,role:'control'};return{code,secret,expiresAt}}
 pair(value:string,name:string){const i=this.invite;if(!i||i.expiresAt<=this.now())throw Error('配对码已过期，请在电脑重新生成');const hash=digest(String(value||''));if(!timingSafeEqual(Buffer.from(hash),Buffer.from(i.code))&&!timingSafeEqual(Buffer.from(hash),Buffer.from(i.secret))){i.attempts++;if(i.attempts>=5)this.invite=undefined;throw Error('配对码错误；连续 5 次错误后需要重新生成')}this.invite=undefined;return this.enroll(name,i.role)}
}
export function localBootstrap(req:any){return['127.0.0.1','::1','::ffff:127.0.0.1'].includes(req.socket.remoteAddress)&&['localhost','127.0.0.1','[::1]'].includes(req.hostname)&&!req.get('x-forwarded-for')&&!req.get('x-forwarded-host')&&!req.get('tailscale-user-login')}
export function cookieToken(req:any){const value=String(req.headers.cookie||'').split(';').map(v=>v.trim()).find(v=>v.startsWith('gcollie_device='));return value?value.slice('gcollie_device='.length):''}
export function sameOrigin(req:any){const origin=req.get('origin');if(!origin)return true;try{return new URL(origin).host===req.get('host')}catch{return false}}
export function writeDeviceCookie(req:any,res:any,token:string){const secure=req.secure||req.get('x-forwarded-proto')==='https';res.cookie('gcollie_device',token,{httpOnly:true,sameSite:'strict',secure,path:'/',maxAge:90*86400000})}
