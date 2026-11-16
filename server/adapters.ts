/** Metadata reports confirmed control, separately from implemented support and prerequisites.
 * This projection never connects to, activates, or starts an Agent session.
 */
export function adapterSummaries(sessions:any[],options:{role:string;codexEnabled:boolean;codexLiveIds:string[];claudeInstalled:boolean}){
 return ['Codex','Hermes','Claude Code'].map(agent=>{
  const rows=sessions.filter(s=>s.agent===agent),permitted=options.role!=='view';
  const enabled=permitted&&(agent!=='Codex'||options.codexEnabled);
  const confirmed=enabled?rows.filter(s=>!s.archived&&(agent==='Codex'?options.codexLiveIds.includes(s.nativeId):agent==='Claude Code'?options.claudeInstalled&&s.readOnly===false:false)).length:0;
  const condition=agent==='Codex'?'控制开关已启用，且原会话桌面客户端已连接；实际状态以会话详情为准':agent==='Hermes'?'Hermes 本机后端可连接，且原会话已加载；本接口不主动连接或恢复会话':'本机已安装 Claude Code CLI，且会话由 G-Collie 创建；终端历史只读';
  return{agent,state:confirmed?'available':enabled?'conditional':'readonly',detail:`已接入 ${rows.length} 个会话 · ${!permitted?'当前设备只读':agent==='Codex'&&!options.codexEnabled?'Codex 控制未启用':condition}`,capabilities:{history:true,usage:true,control:confirmed>0},control:{supported:true,enabled,availability:confirmed?'confirmed':enabled?'session-dependent':'disabled',confirmedSessions:confirmed,condition}};
 });
}
