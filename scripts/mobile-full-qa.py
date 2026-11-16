"""Android fixture QA only: memory state and loopback, never proxies real APIs.
Run python3 scripts/mobile-full-qa.py and adb reverse tcp:4398 tcp:4398.
Pair a separate G-Collie QA app with http://127.0.0.1:4398 and code 123456.
Responses simulate Agent actions; passing this does not prove upstream Agent compatibility.
"""
import json,time,pathlib
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from urllib.parse import unquote,urlparse,parse_qs
ROOT=pathlib.Path(__file__).resolve().parent.parent;now=int(time.time()*1000)
sessions=[dict(id=agent.lower().replace(' ','')+':qa'+str(i),nativeId='qa'+str(i),agent=agent,title=agent+' 隔离验收 '+str(i),cwd='/qa/project',project='验收项目',projectPath='/qa/project',updatedAt=now-i*60000,archived=False,desktopLive=True,desktopControl=True,hermesLive=agent=='Hermes',claudeLive=agent=='Claude Code',status='idle',events=[dict(id='question',role='user',text='请核对隔离界面'),dict(id='reply',role='assistant',text='隔离测试回复：**完成界面核对**。\n\n- 加载与权限独立验证\n- 不连接真实 Agent')]) for agent in ['Codex','Hermes','Claude Code'] for i in range(5)]
projects=[dict(path='/qa/project',name='验收项目',sessions=15)]
metric=dict(total=12345,input=10000,output=2345,cached=5000,cacheWrite=0,reasoning=200,requests=3,cacheRate=.5,unclassified=0)
agentusage=dict(today=metric,month=metric,total=metric,daily=[dict(date='2026-11-14',usage=metric)],monthly=[dict(month='2026-11',usage=metric)],projects=[dict(path='/qa/project',name='验收项目',sessions=15,usage=metric)],sessions=[dict(id=sessions[0]['id'],title='隔离会话',project='验收项目',usage=metric)],models=[dict(model='fixture-model',usage=metric)],coverage=dict(sessions=5,withUsage=5,missingFiles=0,undated=dict(total=0)))
usage=dict(agents={a:agentusage for a in ['Codex','Hermes','Claude Code']},codexAccount=dict(accountKey='fixture-account',accountLabel='隔离测试账号',usage=dict(summary=dict(lifetimeTokens=12345,peakDailyTokens=12345),dailyUsageBuckets=[dict(startDate='2026-11-14',tokens=12345)]),limits=[dict(id='qa',name='隔离额度',windows=[dict(windowMinutes=300,usedPercent=25,resetsAt=time.time()+3600),dict(windowMinutes=10080,usedPercent=10,resetsAt=time.time()+86400)])],fetchedAt=now,resetCredits=dict(availableCount=1,credits=[dict(id='qa',title='模拟卡片',status='available',expiresAt=time.time()+86400)])),generatedAt=now,timezone='Asia/Shanghai',trackingSince=now,warnings=[])
state=dict(role='owner',mode='normal',writes=[],tasks=[],goal='',plan='default',paired=False)
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT/'dist'),**kw)
 def log_message(self,*a):pass
 def response(self,data,status=200):
  raw=json.dumps(data,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Set-Cookie','gcollie_device=qa-only; Path=/; SameSite=Strict') if state['paired'] else None;self.end_headers();self.wfile.write(raw)
 def do_GET(self):
  url=urlparse(self.path);path=unquote(url.path);q=parse_qs(url.query)
  if path=='/healthz':self.response(dict(ok=True,version='0.3.24'));return
  if path=='/api/events':
   self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
   try:
    for _ in range(180):self.wfile.write(b': heartbeat\n\n');self.wfile.flush();time.sleep(10)
   except (BrokenPipeError,ConnectionResetError):pass
   return
  if path=='/qa-state':self.response(state);return
  if path=='/qa-config':
   for k in ['role','mode']:state[k]=q.get(k,[state[k]])[0]
   if q.get('history')==['long']:
    for session in sessions:
     session['events']=[dict(id='history-'+str(i),role='assistant',text=('隔离历史记录 '+str(i)+'\n')*12,time=now-60000+i,media=[]) for i in range(50)]+[dict(id='latest-marker',role='assistant',text='LATEST_QA_MESSAGE',time=now,media=[])]
   self.response(state);return
  if not path.startswith('/api/'):return super().do_GET()
  p=path[4:]
  if state['mode']=='failure' and p in ['/schedules','/usage','/diagnostics']:self.response(dict(error='隔离网络暂不可用，请重试'),503);return
  if p=='/auth/status':data=dict(paired=state['paired'],device=dict(role=state['role']))
  elif p=='/local':data=dict(sessions=sessions,projects=projects,warnings=[])
  elif p.startswith('/local/'):
   suffix=p[7:];s=next((s for s in sessions if suffix.startswith(s['id'])),sessions[0])
   if suffix.endswith('/resources'):
    if state['mode']=='failure':self.response(dict(error='隔离文件读取失败'),503);return
    data=dict(resources=[dict(id='document',name='验收说明.md',image=False)])
   elif suffix.endswith('/codex-capabilities'):data=dict(mode=state['plan'],modes=dict(data=dict(data=[dict(mode='default'),dict(mode='plan')])),goal=dict(data=dict(goal=dict(objective=state['goal']))),skills=[dict(id='qa-skill',plugin='隔离插件',name='验收技能')])
   else:
    data={**s,'readOnly':state['role']=='view'}
    if state['mode']=='running':data={**data,'status':'running','turnId':'qa-turn'}
    if state['mode']=='approval':data={**data,'status':'waiting','pending':dict(id='qa-approve',kind='approval',params=dict(command='echo QA_ONLY',availableDecisions=['accept','decline']))}
    if state['mode']=='question':data={**data,'status':'waiting','pending':dict(id='qa-question',kind='question',params=dict(questions=[dict(id='q',question='验收选项',options=[dict(label='简洁',description='必要信息'),dict(label='详细',description='完整说明')])]))}
    if state['mode']=='unsupported':data={**data,'status':'waiting','pending':dict(id='qa-host-question',kind='unsupported',params=dict(reason='宿主异步问题请在电脑处理'))}
    if state['mode']=='offline':data={**data,'desktopLive':False,'desktopControl':False,'desktopError':'隔离连接断开，状态未知','status':'unknown'}
  elif p=='/folders':data=dict(path='/qa',parent=None,folders=[dict(name='验收项目',path='/qa/project')])
  elif p in ['/usage','/usage/limits']:data=usage
  elif p=='/schedules':data=dict(tasks=state['tasks'])
  elif p=='/devices':data=dict(devices=[dict(id='owner',name='隔离管理端',role='owner',lastSeenAt=now),dict(id='phone',name='隔离手机',role='control',lastSeenAt=now)],currentDeviceId='owner',inviteActive=True)
  elif p=='/network':data=dict(computerName='隔离测试电脑',tailscale=dict(installed=False),pairingAddresses=['http://127.0.0.1:4398'],addresses=[])
  elif p=='/network/embedded':data=dict(available=True,state='Stopped')
  elif p=='/diagnostics/system':data=dict(version='0.3.24',uptimeSeconds=100,codex=dict(available=True,controlEnabled=True))
  elif p=='/diagnostics':data=dict(checks=[dict(name='隔离服务',status='正常',detail='模拟环境，不连接生产')],recent=[])
  elif p=='/diagnostics/requests':data=dict(requests=[])
  else:self.response(dict(error='无此隔离接口：'+p),404);return
  self.response(data)
 def do_POST(self):
  p=unquote(urlparse(self.path).path)[4:]
  raw=b''
  if self.headers.get('Transfer-Encoding','').lower()=='chunked':
   while True:
    size=int(self.rfile.readline().strip().split(b';')[0],16)
    if not size:self.rfile.readline();break
    raw+=self.rfile.read(size);self.rfile.read(2)
  else:raw=self.rfile.read(int(self.headers.get('Content-Length',0)))
  body=json.loads(raw or '{}') if 'application/json' in self.headers.get('Content-Type','') else {'bytes':len(raw)}
  state['writes'].append(dict(path=p,body={k:v for k,v in body.items() if k not in ['data','content','base64']}))
  if p=='/auth/pair':
   if body.get('code')!='123456':self.response(dict(error='配对码无效'),403);return
   state['paired']=True;self.response(dict(device=dict(role='control'),ok=True));return
  if p=='/attachments':self.response(dict(id='qa-upload-'+str(len(state['writes'])),name=body.get('name','验收附件'),image=True,size=10));return
  if p=='/usage/codex/reset':self.response(dict(error='验收禁止消费重置卡'),403);return
  if p=='/auth/logout':state['paired']=False;self.response(dict(ok=True));return
  if p=='/devices/pair':self.response(dict(code='123456',qr='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>',url='http://127.0.0.1:4398/#pair=123456',expiresAt=now+600000));return
  if p=='/sessions':
   s={**sessions[0],'id':'codex:newqa','nativeId':'newqa','agent':body.get('agent','Codex'),'title':body.get('title') or '隔离新会话','events':[dict(id='new-input',role='user',text=body.get('prompt',''))]};sessions.append(s);self.response(s);return
  if p=='/projects':projects.append(dict(name=body['name'],path=body['path'],sessions=0));self.response(projects[-1]);return
  if p=='/schedules':state['tasks'].append({**body,'id':'qa-task','status':'pending'});self.response(dict(ok=True));return
  if p.endswith('/goal'):state['goal']=body.get('objective','')
  if p.endswith('/mode'):state['plan']=body.get('mode','default')
  if p.startswith(('/desktop/','/hermes/','/claude/')):
   if body.get('action')=='send':
    target=next((s for s in sessions if s['nativeId']==p.split('/')[-1] and s['agent']==('Hermes' if p.startswith('/hermes/') else 'Claude Code' if p.startswith('/claude/') else 'Codex')),sessions[0])
    target['events'].append(dict(id='sent'+str(len(state['writes'])),role='user',text=body.get('text',''),attachmentIds=body.get('attachments',[]),time=int(time.time()*1000),turnId='qa-sent-turn'))
   if body.get('action') in ['send','stop','answer']:state['mode']='normal'
  if p=='/shares':self.response(dict(id='qa-share',url='http://127.0.0.1:4398/s/qa-share'));return
  self.response(dict(ok=True,turnId='qa-sent-turn'))
print('http://127.0.0.1:4398',flush=True);ThreadingHTTPServer(('127.0.0.1',4398),Handler).serve_forever()
