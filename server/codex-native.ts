import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {existsSync} from 'node:fs';
import {codexEnvironment} from './codex.js';
/** Narrow native protocol adapter. No prompting, tool execution or plugin installation. */
export async function nativeCodex(root:string,method:string,params:any){
 if(!['collaborationMode/list','plugin/installed','thread/goal/get','thread/goal/set','thread/goal/clear','thread/archive'].includes(method))throw Error('未允许的原生操作');
 const bin=process.env.ORBIT_CODEX_BIN||process.env.CODEX_CLI_PATH||(existsSync('/usr/lib/chatgpt/resources/codex')?'/usr/lib/chatgpt/resources/codex':'codex');
 const child=spawn(bin,['app-server','--listen','stdio://'],{stdio:'pipe',env:codexEnvironment(root)});let seq=0;const pending=new Map<number,{resolve:(v:any)=>void;reject:(e:Error)=>void}>();const lines=createInterface({input:child.stdout});
 const fail=(e:Error)=>{for(const p of pending.values())p.reject(e);pending.clear()};child.on('error',fail);child.on('exit',()=>fail(Error('原生能力连接已关闭')));child.stderr.on('data',()=>{});
 lines.on('line',line=>{try{const r=JSON.parse(line),p=pending.get(r.id);if(p){pending.delete(r.id);r.error?p.reject(Error(r.error.message)):p.resolve(r.result)}}catch{}});
 const rpc=(method:string,params:any)=>new Promise<any>((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});child.stdin.write(JSON.stringify({id,method,params})+'\n')});
 const timer=setTimeout(()=>{fail(Error('原生能力响应超时，写入结果未知，请刷新确认'));child.kill()},15000);
 try{await rpc('initialize',{clientInfo:{name:'gcollie_capabilities',version:'0.3.16'},capabilities:{experimentalApi:true}});child.stdin.write('{"method":"initialized"}\n');return await rpc(method,params)}finally{clearTimeout(timer);lines.close();child.kill()}
}
export function goalParams(nativeId:string,body:any){if(!/^[a-zA-Z0-9_-]+$/.test(nativeId))throw Error('无效会话编号');if(body.action==='clear')return{method:'thread/goal/clear',params:{threadId:nativeId}};if(body.action!=='set'||typeof body.objective!=='string'||!body.objective.trim()||body.objective.length>4000)throw Error('请输入 1–4000 字目标');if(body.tokenBudget!=null&&(!Number.isSafeInteger(body.tokenBudget)||body.tokenBudget<=0))throw Error('预算需为正整数');return{method:'thread/goal/set',params:{threadId:nativeId,objective:body.objective.trim(),...(body.tokenBudget?{tokenBudget:body.tokenBudget}:{})}}}

export async function installedSkills(root:string){
 const {readdir,realpath,stat}=await import('node:fs/promises');const {join,relative}=await import('node:path');const catalog=await nativeCodex(root,'plugin/installed',{});const result:{id:string;name:string;path:string;plugin:string}[]=[];
 for(const market of catalog.marketplaces||[])for(const p of market.plugins||[]){if(!p.enabled||!p.installed||p.source?.type!=='local')continue;try{const base=await realpath(p.source.path),folder=join(base,'skills');for(const entry of (await readdir(folder)).slice(0,100)){const path=await realpath(join(folder,entry,'SKILL.md'));if(relative(base,path).startsWith('..')||!(await stat(path)).isFile())continue;result.push({id:p.id+':'+entry,name:entry,path,plugin:p.interface?.displayName||p.name});}}catch{}}
 return result;
}
export async function resolveSkills(root:string,ids:any){if(ids==null)return[];if(!Array.isArray(ids)||ids.length>5||ids.some(i=>typeof i!=='string'))throw Error('插件技能选择无效');const catalog=await installedSkills(root);return [...new Set(ids)].map(id=>{const skill=catalog.find(s=>s.id===id);if(!skill)throw Error('所选插件未启用或已移除，请重新选择');return{type:'skill',name:skill.name,path:skill.path}})}
