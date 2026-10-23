"""Read-only, allowlisted session projection. Never exports settings or credentials."""
import json,sqlite3,pathlib,sys,datetime,re,os
from message_display import display_text
from process_records import ProcessRecords
HOME=pathlib.Path.home()
def db(path):
 c=sqlite3.connect(path.resolve().as_uri()+'?mode=ro',uri=True,timeout=3);c.row_factory=sqlite3.Row;c.execute('PRAGMA query_only=ON');return c
def ms(v):
 if isinstance(v,(int,float)):return int(v*1000) if v<1e12 else int(v)
 try:return int(datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()*1000)
 except:return 0
def clean(v):
 if isinstance(v,str):return v[:24000]
 if isinstance(v,list):return '\n'.join(str(x.get('text','')) for x in v if isinstance(x,dict) and x.get('type') in ['text','input_text','output_text'])[:24000]
 return ''
try:APP_STATE=json.loads((HOME/'.codex/.codex-global-state.json').read_text())
except:APP_STATE={}
REGISTERED=APP_STATE.get('local-projects',{})
PROJECTLESS=set(APP_STATE.get('projectless-thread-ids',[]))
try:
 FOLDER_DATA=pathlib.Path(os.environ.get('GCOLLIE_DATA_DIR',str(pathlib.Path.cwd()/'.data')))
 FOLDER_PROJECTS={p['path']:p for p in json.loads((FOLDER_DATA/'folder-projects.json').read_text())}
 FOLDER_ASSIGNMENTS=json.loads((FOLDER_DATA/'folder-session-projects.json').read_text())
except:FOLDER_PROJECTS={};FOLDER_ASSIGNMENTS={}
def project_for(agent,r,cwd):
 folder=FOLDER_PROJECTS.get(FOLDER_ASSIGNMENTS.get(r['id']))
 if folder:return dict(path=folder['path'],name=folder['name'])
 if agent=='Codex':
  if r['id'] in PROJECTLESS:return None
  assignment=APP_STATE.get('thread-project-assignments',{}).get(r['id'],{})
  p=REGISTERED.get(assignment.get('projectId'))
  if p and p.get('rootPaths'):return dict(path=p['rootPaths'][0],name=p.get('name') or pathlib.Path(p['rootPaths'][0]).name)
 if not cwd:return None
 path=pathlib.Path(cwd)
 matches=[(root,p) for p in REGISTERED.values() for root in p.get('rootPaths',[]) if path==pathlib.Path(root) or path.is_relative_to(pathlib.Path(root))]
 if matches:
  root,p=max(matches,key=lambda x:len(x[0]));return dict(path=root,name=p.get('name') or pathlib.Path(root).name)
 if agent=='Hermes' and r.get('git_repo_root'):
  root=r['git_repo_root'];return dict(path=root,name=pathlib.Path(root).name)
 return None
def summary(agent,r):
 cwd=r.get('cwd') or r.get('git_repo_root') or ''
 p=project_for(agent,r,cwd)
 return dict(projectPath=p['path'] if p else None,id=agent.lower()+':'+r['id'],nativeId=r['id'],agent=agent,title=(r.get('name') or r.get('title') or '未命名会话')[:160],cwd=cwd,project=p['name'] if p else '无项目',branch=r.get('git_branch'),model=r.get('model'),updatedAt=ms(r.get('updated_at_ms') or r.get('updated_at') or r.get('last_activity_at') or r.get('started_at')),archived=bool(r.get('archived')),status='unknown',readOnly=True,usage=None)
def codexdb():
 files=list((HOME/'.codex').glob('state_*.sqlite'))
 return db(max(files,key=lambda p:p.stat().st_mtime)) if files else None
mode=sys.argv[1]; key=sys.argv[2] if len(sys.argv)>2 else ''
result={'sessions':[],'projects':[],'warnings':[]}
if mode=='list':
 try:
  c=codexdb()
  if c:
   for row in c.execute('SELECT id,title,name,cwd,git_branch,model,updated_at_ms,updated_at,archived FROM threads ORDER BY updated_at DESC LIMIT 500'):result['sessions'].append(summary('Codex',dict(row)))
 except Exception as e:result['warnings'].append('Codex: '+str(e))
 try:
  with db(HOME/'.hermes/state.db') as c:
   for row in c.execute('SELECT id,title,cwd,git_repo_root,git_branch,model,started_at,last_activity_at,archived,input_tokens,output_tokens,cache_read_tokens FROM sessions WHERE hidden=0 ORDER BY COALESCE(last_activity_at,started_at) DESC LIMIT 500'):
    r=dict(row);s=summary('Hermes',r);s['usage']={'input':r['input_tokens'],'output':r['output_tokens'],'cached':r['cache_read_tokens'],'semantics':'provider-reported'};result['sessions'].append(s)
 except Exception as e:result['warnings'].append('Hermes: '+str(e))
 projects={}
 for s in result['sessions']:
  if s['projectPath']:
   p=projects.setdefault(s['projectPath'],dict(path=s['projectPath'],name=s['project'],agents=[],sessions=0))
   p['sessions']+=1
   if s['agent'] not in p['agents']:p['agents'].append(s['agent'])
 result['projects']=list(projects.values());result['sessions'].sort(key=lambda s:s['updatedAt'],reverse=True)
else:
 agent,native=key.split(':',1);events=[];usage=None;modern_usage=False;process=ProcessRecords(events)
 if agent=='codex':
  c=codexdb();row=c.execute('SELECT id,title,name,cwd,git_branch,model,updated_at_ms,updated_at,archived,rollout_path FROM threads WHERE id=?',(native,)).fetchone()
  if not row:raise ValueError('会话不存在')
  row=dict(row);result=summary('Codex',row);path=pathlib.Path(row['rollout_path']).resolve();allowed=[(HOME/'.codex/sessions').resolve(),(HOME/'.codex/archived_sessions').resolve()]
  if not any(path.is_relative_to(root) for root in allowed):raise ValueError('会话文件超出允许范围')
  with path.open() as f:
   for index,line in enumerate(f):
    try:d=json.loads(line)
    except:continue
    p=d.get('payload',{});kind=d.get('type');text='';role='';media=[]
    if process.feed(kind,p,ms(d.get('timestamp')),index):continue
    if kind=='response_item':
     t=p.get('type')
     if t=='message' and p.get('role') in ['user','assistant']:
      role=p['role'];text=clean(p.get('content'))
      for part in p.get('content',[]) if isinstance(p.get('content'),list) else []:
       if isinstance(part,dict) and part.get('type') in ['image','input_image','output_image','local_image','localImage']:
        value=part.get('image_url') or part.get('url') or part.get('path');value=value.get('url') if isinstance(value,dict) else value
        if isinstance(value,str) and len(value)<8*1024*1024:media.append(value)
      text=re.sub(r'<(environment_context|external_codex_apps_open_page|in-app-browser-context)\b[^>]*>.*?</\1>', '', text, flags=re.S).strip()
     elif t in ['function_call','custom_tool_call']:role='tool';text='调用 '+str(p.get('name','tool'))
     elif t in ['function_call_output','custom_tool_call_output']:role='tool';text=clean(p.get('output'))
    if kind=='token_usage_record':
     modern_usage=True;u=p.get('thread_token_usage') or {};usage={'input':u.get('input_tokens'),'output':u.get('output_tokens'),'cached':u.get('cached_input_tokens'),'semantics':'includes-cache'}
    if kind=='event_msg' and p.get('type')=='token_count' and not modern_usage:
     u=(p.get('info') or {}).get('total_token_usage') or {};usage={'input':u.get('input_tokens'),'output':u.get('output_tokens'),'cached':u.get('cached_input_tokens'),'semantics':'includes-cache'}
    text=display_text(text,role,bool(media))
    if text or media:events.append(dict(id=str(index),role=role,text=text,media=media,phase=p.get('channel'),time=ms(d.get('timestamp'))))
 elif agent=='hermes':
  with db(HOME/'.hermes/state.db') as c:
   row=c.execute('SELECT id,title,cwd,git_repo_root,git_branch,model,started_at,last_activity_at,archived,input_tokens,output_tokens,cache_read_tokens FROM sessions WHERE id=? AND hidden=0',(native,)).fetchone()
   if not row:raise ValueError('会话不存在')
   r=dict(row);result=summary('Hermes',r);usage={'input':r['input_tokens'],'output':r['output_tokens'],'cached':r['cache_read_tokens'],'semantics':'provider-reported'}
   for row in reversed(list(c.execute("SELECT id,role,content,tool_name,tool_calls,tool_call_id,display_kind,timestamp FROM messages WHERE session_id=? AND role IN ('user','assistant','tool') ORDER BY id DESC LIMIT 200",(native,)))):
    r=dict(row);content=r['content'];media=[]
    if r.get('display_kind') in ['hidden','internal_notification']:continue
    if r['role']=='user':process.turn='user:'+str(r['id'])
    if r['role']=='tool':
     process.finish(r.get('tool_call_id') or str(r['id']),content,ms(r['timestamp']),r.get('tool_name') or '工具');continue
    if isinstance(content,str) and content.lstrip().startswith('['):
     try:content=json.loads(content)
     except:pass
    if isinstance(content,list):
     for part in content:
      if isinstance(part,dict) and part.get('type') in ['image','image_url','input_image','local_image','localImage']:
       value=part.get('image_url') or part.get('url') or part.get('path');value=value.get('url') if isinstance(value,dict) else value
       if isinstance(value,str) and len(value)<8*1024*1024:media.append(value)
    text=clean(content) or ('工具 '+str(r['tool_name']) if r['tool_name'] else '')
    text=display_text(text,r['role'],bool(media))
    if text.strip() or media:events.append(dict(id=str(r['id']),role=r['role'],text=text,media=media,phase='commentary' if r.get('tool_calls') else None,time=ms(r['timestamp'])))
    calls=r.get('tool_calls')
    try:calls=json.loads(calls) if isinstance(calls,str) else calls
    except:calls=[]
    for call in calls if isinstance(calls,list) else []:
     f=call.get('function') or {};process.start(call.get('id') or call.get('call_id'),f.get('name','工具'),f.get('arguments',''),ms(r['timestamp']),str(r['id'])+':'+str(call.get('id')))
 else:raise ValueError('未知 Agent')
 result.update(events=events[-200:],usage=usage,historyLimit=200,latestProcessTurnId=process.turn)
print(json.dumps(result,ensure_ascii=False))
