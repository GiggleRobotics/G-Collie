import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {hermesGatewayTicket} from './hermes.js';
import {DeleteFailure,type DeleteProvider} from './session-deletion.js';
const exec=promisify(execFile);
/** Only the upstream owner commits deletion; never writes an Agent database or transcript. */
export function hermesDeletionProvider(active:()=>Promise<any[]>,dependencies:{origin?:()=>Promise<string>;ticket?:typeof hermesGatewayTicket;fetch?:typeof fetch}={}):DeleteProvider{
 const gatewayTicket=dependencies.ticket||hermesGatewayTicket,remoteFetch=dependencies.fetch||fetch;
 async function origin(){
  if(dependencies.origin)return dependencies.origin();
  let value=process.env.ORBIT_HERMES_URL;
  if(!value){const {stdout}=await exec('ss',['-ltnpH'],{timeout:3000});const ports=stdout.split('\n').filter(l=>/users:\(\("hermes"/.test(l)).map(l=>l.match(/127\.0\.0\.1:(\d+)/)?.[1]).filter(Boolean);if(ports.length!==1)throw Error('Hermes 后端未唯一发现');value='http://127.0.0.1:'+ports[0]}
  const url=new URL(value);if(url.protocol!=='http:'||url.hostname!=='127.0.0.1'||url.username||url.password)throw Error('仅允许本机 Hermes');return url.origin;
 }
 async function request(base:string,path:string,method='GET'){
  const ticket=await gatewayTicket(base,'native-http');return remoteFetch(base+path,{method,headers:{'x-hermes-gateway-ticket':ticket},signal:AbortSignal.timeout(8000)});
 }
 return{
  async inspect(id){
   const base=await origin();const response=await remoteFetch(base+'/api/status',{signal:AbortSignal.timeout(4000)});if(!response.ok)throw Error('Hermes 状态不可用');const status:any=await response.json();if(status.auth_required!==false)throw Error('Hermes 需要正常登录或认证状态无法确认');
   const rows=await active();const row=rows.find(r=>r.session_key===id||r.id===id);
   const deny=(code:string,reason:string)=>({supported:true,allowed:false,code,reason,source:'hermes'});
   if(row&&row.status!=='idle')return deny('delete_busy','执行中、等待处理或状态未知的会话不能删除');
   const result=await request(base,'/api/sessions/'+encodeURIComponent(id));if(!result.ok)throw Error('Hermes 会话状态不可用');const d:any=await result.json();
   if(d.id!==id||!Number.isSafeInteger(d.runtime_revision)||!Number.isSafeInteger(d.runtime_generation)||d.runtime_revision<0||d.runtime_generation<0)return deny('delete_unsupported','此 Hermes 版本缺少原生删除所需的状态保护');
   // An absent active-list row alone does not prove idle. Require an ended stored record.
   if(!row&&!d.ended_at)return deny('delete_unknown_state','会话运行状态尚未确认，请先在电脑检查');
   return{supported:true,allowed:true,code:'delete_allowed',reason:'删除电脑端原始会话及其压缩、重置历史，并撤销分享，无法撤销',source:'hermes',revision:d.runtime_revision,generation:d.runtime_generation};
  },
  async remove(id,requestId,state){
   const base=await origin();const params=new URLSearchParams({request_id:requestId,expected_revision:String(state.revision),expected_generation:String(state.generation)});
   const result=await request(base,'/api/sessions/'+encodeURIComponent(id)+'?'+params,'DELETE');
   if(!result.ok){if(result.status>=500)throw new DeleteFailure('删除结果未知，请先在电脑核对','delete_result_unknown','unknown');throw new DeleteFailure('电脑拒绝删除：会话状态可能已改变，请刷新后重试','delete_rejected')}
   const body:any=await result.json();if(body?.ok!==true)throw new DeleteFailure('删除结果未知，请先在电脑核对','delete_result_unknown','unknown');
   const ids=Array.isArray(body.deleted_ids)?body.deleted_ids:[];if(ids.some((value:any)=>typeof value!=='string'||!/^[a-zA-Z0-9_-]+$/.test(value)))throw new DeleteFailure('删除结果未知，请先在电脑核对','delete_result_unknown','unknown');return{deletedIds:[...new Set([id,...ids])].map(value=>'hermes:'+value)};
  }
 }
}
