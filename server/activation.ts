export class SessionActivation{
 private pending=new Map<string,Promise<any>>();
 run(id:string,activate:()=>Promise<any>){const existing=this.pending.get(id);if(existing)return existing;const task=Promise.resolve().then(activate).finally(()=>this.pending.delete(id));this.pending.set(id,task);return task}
}
export function assertActivatable(detail:any){if(detail.archived)throw Error('此会话已归档，请先在电脑取消归档后继续');if(!['Codex','Hermes'].includes(detail.agent))throw Error('此来源暂不支持恢复执行')}
