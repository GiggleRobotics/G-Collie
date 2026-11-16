import {randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';
export function shareProjection(detail:any){return{title:String(detail.title||'会话').slice(0,160),agent:detail.agent,historyLimit:detail.historyLimit||200,events:(detail.events||[]).filter((e:any)=>['user','assistant'].includes(e.role)&&e.text?.trim()).map((e:any)=>({role:e.role,text:String(e.text).slice(0,24000)}))}}
const escape=(s:any)=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export function shareHTML(s:any){return`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>${escape(s.title)}</title><style>body{max-width:760px;margin:0 auto;padding:32px 22px;font:15px/1.9 system-ui;color:#222;background:#fff}h1{font-size:24px}small{color:#888}article{margin:28px 0;white-space:pre-wrap;overflow-wrap:anywhere}article.user{background:#f4f4f4;padding:16px 20px;border-radius:22px}b{display:block;font-size:12px;color:#888;margin-bottom:8px}</style><h1>${escape(s.title)}</h1><small>${escape(s.agent)} · 只读快照 · 最近 ${s.historyLimit} 条中的文字消息 · ${escape(new Date(s.createdAt).toISOString())}</small>${s.events.map((e:any)=>`<article class="${e.role}"><b>${e.role==='user'?'你':escape(s.agent)}</b>${escape(e.text)}</article>`).join('')}</html>`}
export class ShareStore{
 private rows:Record<string,any>={};
 constructor(private root:string){try{this.rows=JSON.parse(readFileSync(join(root,'shares.json'),'utf8'))}catch{}}
 private save(){const p=join(this.root,'shares.json');writeFileSync(p+'.tmp',JSON.stringify(this.rows),{mode:0o600});renameSync(p+'.tmp',p)}
 create(id:string,detail:any,requestId:string){if(!/^[a-zA-Z0-9_-]{8,100}$/.test(requestId||''))throw Error('无效分享操作编号');const existing=Object.entries(this.rows).find(([,v])=>v.sessionId===id&&v.requestId===requestId&&v.expiresAt>Date.now());if(existing)return{key:existing[0],expiresAt:existing[1].expiresAt};const key=randomBytes(24).toString('hex');const now=Date.now();this.rows[key]={...shareProjection(detail),sessionId:id,requestId,createdAt:now,expiresAt:now+7*86400000};this.save();return{key,expiresAt:this.rows[key].expiresAt}}
 latest(id:string){const row=Object.entries(this.rows).filter(([,v])=>v.sessionId===id&&v.expiresAt>Date.now()).sort((a,b)=>b[1].createdAt-a[1].createdAt)[0];return row?{key:row[0],expiresAt:row[1].expiresAt}:null}
 get(key:string){const s=this.rows[key];return /^[a-f0-9]{48}$/.test(key)&&s&&s.expiresAt>Date.now()?s:null}
 revokeSession(id:string){for(const[key,row]of Object.entries(this.rows))if(row.sessionId===id)delete this.rows[key];this.save()}
 revoke(id:string,key:string){if(this.rows[key]?.sessionId!==id)throw Error('分享不存在');delete this.rows[key];this.save()}
}
