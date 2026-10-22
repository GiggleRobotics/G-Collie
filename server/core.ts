export type Status = 'running'|'waiting'|'completed'|'stopped';
export interface Task {id:string; title:string; agent:'Codex'|'Hermes'; project:string; status:Status; demo:boolean; updatedAt:number; input:number; output:number; cached:number; events:{id:string;time:number;kind:string;text:string}[]; approval?:{id:string;text:string};}
export function applyAction(task:Task, action:string, text?:string, approvalId?:string) {
 if(!task.demo) throw new Error('此适配器暂不支持控制');
 if(action==='stop') {if(!['running','waiting'].includes(task.status))throw new Error('任务已结束');task.status='stopped';delete task.approval;}
 else if(action==='message') {if(!text?.trim())throw new Error('消息不能为空');if(text.length>4000)throw new Error('消息过长');task.status='running';}
 else if(action==='approve'||action==='deny') {if(!task.approval||task.approval.id!==approvalId)throw new Error('审批已失效，请刷新'); delete task.approval;task.status=action==='approve'?'running':'stopped';}
 else throw new Error('未知操作');
 task.updatedAt=Date.now();task.events.push({id:crypto.randomUUID(),time:task.updatedAt,kind:action,text:action==='message'?text!:action==='stop'?'已停止演示任务':action==='approve'?'已批准演示请求':'已拒绝演示请求'});
}
export function seeds():Task[]{const now=Date.now();return [
 {id:'demo-codex',title:'构建移动端 AI 工作控制台',agent:'Codex',project:'agent-console',status:'running',demo:true,updatedAt:now,input:18420,output:3260,cached:12000,events:[{id:'e1',time:now-120000,kind:'plan',text:'实现电脑服务、任务看板与实时事件流'},{id:'e2',time:now-60000,kind:'tool',text:'正在搭建 Agent 适配器与移动端界面'}]},
 {id:'demo-hermes',title:'整理项目工作记录',agent:'Hermes',project:'workspace',status:'waiting',demo:true,updatedAt:now-60000,input:8240,output:1640,cached:4000,approval:{id:'approval-demo',text:'演示：请求读取项目目录并生成工作记录'},events:[{id:'e3',time:now-60000,kind:'approval',text:'等待你的确认后继续执行'}]},
 {id:'demo-done',title:'检查运行环境',agent:'Codex',project:'agent-console',status:'completed',demo:true,updatedAt:now-180000,input:2160,output:480,cached:1000,events:[{id:'e4',time:now-180000,kind:'result',text:'环境检查完成。此任务为演示数据。'}]}];}
