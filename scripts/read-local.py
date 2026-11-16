"""Read-only, allowlisted session projection. Never exports settings or credentials."""
from path_compat import is_relative_to
import json,sqlite3,pathlib,sys,datetime,re,os,hashlib,base64
from message_display import visible_user_media, display_text, hermes_internal_message, hermes_message, hermes_background_events, codex_created_input, codex_generated_image, group_generated_images, codex_user_text
from process_records import ProcessRecords
from history_page import history_page
HOME=pathlib.Path.home()
def db(path):
 c=sqlite3.connect(path.resolve().as_uri()+'?mode=ro',uri=True,timeout=3);c.row_factory=sqlite3.Row;c.execute('PRAGMA query_only=ON');return c
def hermes_display_rows(connection, native):
 # Hermes copies protected messages across compaction generations. Identity includes
 # the original timestamp and tool linkage; equal text from separate sends is distinct.
 rows=connection.execute("SELECT * FROM messages WHERE session_id=? AND role IN ('user','assistant','tool') ORDER BY id ASC",(native,))
 seen={};order={}
 for row in rows:
  r=dict(row)
  if 'active' in r and not (r.get('active') or r.get('compacted')):continue
  metadata=r.get('display_metadata')
  try:metadata=json.loads(metadata) if isinstance(metadata,str) else metadata
  except (ValueError,TypeError):metadata=None
  if isinstance(metadata,dict) and metadata.get('model_only'):continue
  identity=r.get('display_identity')
  legacy=(r['role'],r.get('content'),r.get('timestamp'),r.get('tool_call_id'),r.get('tool_calls'),r.get('tool_name'))
  key=bytes(identity) if identity is not None else hashlib.sha256(repr(legacy).encode('utf-8','surrogatepass')).digest()
  order.setdefault(key,r.get('display_order') if r.get('display_order') is not None else r['id'])
  old=seen.get(key)
  if old is None or (r.get('active',1),r['id'])>(old.get('active',1),old['id']):seen[key]=r
 return [dict(seen[key],id=order[key]) for key in sorted(seen,key=order.get)]
def ms(v):
 if isinstance(v,(int,float)):return int(v*1000) if v<1e12 else int(v)
 try:return int(datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()*1000)
 except:return 0
def clean(v,limit=24000):
 if isinstance(v,str):return v[:limit]
 if isinstance(v,list):return '\n'.join(str(x.get('text','')) for x in v if isinstance(x,dict) and x.get('type') in ['text','input_text','output_text'])[:limit]
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
 matches=[(root,p) for p in REGISTERED.values() for root in p.get('rootPaths',[]) if path==pathlib.Path(root) or is_relative_to(path, pathlib.Path(root))]
 if matches:
  root,p=max(matches,key=lambda x:len(x[0]));return dict(path=root,name=p.get('name') or pathlib.Path(root).name)
 if agent=='Hermes' and r.get('git_repo_root'):
  root=r['git_repo_root'];return dict(path=root,name=pathlib.Path(root).name)
 return None
def summary(agent,r):
 cwd=r.get('cwd') or r.get('git_repo_root') or ''
 p=project_for(agent,r,cwd)
 return dict(projectPath=p['path'] if p else None,id=agent.lower()+':'+r['id'],nativeId=r['id'],agent=agent,title=(r.get('name') or r.get('title') or '未命名会话')[:160],cwd=cwd,project=p['name'] if p else '无项目',branch=r.get('git_branch'),model=r.get('model'),updatedAt=ms(r.get('updated_at_ms') or r.get('updated_at') or r.get('last_activity_at') or r.get('started_at')),archived=bool(r.get('archived')),status='unknown',readOnly=True,usage=None)
def photo_names(media,text):
 names=[]
 uploads=(pathlib.Path(os.environ.get('GCOLLIE_DATA_DIR',str(pathlib.Path.cwd()/'.data')))/'uploads').resolve()
 for ref in media:
  if ref.startswith('data:'):continue
  try:
   path=pathlib.Path(ref).resolve()
   if not is_relative_to(path, uploads):continue
   relative=path.relative_to(uploads)
   if len(relative.parts)!=3 or not re.fullmatch(r'[a-f0-9-]{36}',relative.parts[0]) or relative.parts[1:]!=('media','image.jpg'):continue
   meta=json.loads((uploads/relative.parts[0]/'meta.json').read_text())
   if meta.get('image') and meta.get('session')==key:names.append(meta['name'])
  except (OSError,ValueError,TypeError,KeyError):pass
 labels=set(re.findall(r'(?m)^照片：([^\r\n]+)$',text))
 if labels and any(ref.startswith('data:image/') for ref in media):
  digests=set()
  for ref in media:
   if ref.startswith('data:image/'):
    try:digests.add(hashlib.sha256(base64.b64decode(ref.split(',',1)[1],validate=True)).digest())
    except (ValueError,IndexError):pass
  try:folders=list(uploads.iterdir())
  except OSError:folders=[]
  for folder in folders:
   try:
    if not re.fullmatch(r'[a-f0-9-]{36}',folder.name):continue
    meta=json.loads((folder/'meta.json').read_text())
    if meta.get('image') and meta.get('session')==key and meta.get('name') in labels and hashlib.sha256((folder/'media/image.jpg').read_bytes()).digest() in digests:names.append(meta['name'])
   except (OSError,ValueError,TypeError,KeyError):pass
 return names
def codexdb():
 files=list((HOME/'.codex').glob('state_*.sqlite'))
 return db(max(files,key=lambda p:p.stat().st_mtime)) if files else None
mode=sys.argv[1]; key=sys.argv[2] if len(sys.argv)>2 else ''
options=json.loads(sys.argv[3]) if len(sys.argv)>3 else {}
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
  if not any(is_relative_to(path, root) for root in allowed):raise ValueError('会话文件超出允许范围')
  generated_seen=set()
  with path.open() as f:
   for index,line in enumerate(f):
    try:d=json.loads(line)
    except:continue
    p=d.get('payload',{});kind=d.get('type');text='';role='';media=[]
    created_input=codex_created_input(kind,p)
    if created_input is not None:
     events.append(dict(id=p.get('id') or str(index),role='user',text=created_input,media=[],time=ms(d.get('timestamp')),turnId=(p.get('internal_chat_message_metadata_passthrough') or {}).get('turn_id')));continue
    generated=codex_generated_image(kind,p,HOME,native)
    if generated:
     if generated not in generated_seen:
      generated_seen.add(generated)
      events.append(dict(id='generated:'+str((p.get('item') or {}).get('id',index)),role='assistant',text='',media=[generated],time=ms(d.get('timestamp')),turnId=p.get('turn_id')))
     continue
    if process.feed(kind,p,ms(d.get('timestamp')),index):continue
    if kind=='response_item':
     t=p.get('type')
     if t=='message' and p.get('role') in ['user','assistant']:
      role=p['role'];text=clean(p.get('content'),None if role=='user' else 24000)
      if role=='user':text=codex_user_text(text)[:24000]
      for part in p.get('content',[]) if isinstance(p.get('content'),list) else []:
       if isinstance(part,dict) and part.get('type') in ['image','input_image','output_image','local_image','localImage']:
        value=part.get('image_url') or part.get('url') or part.get('path');value=value.get('url') if isinstance(value,dict) else value
        if isinstance(value,str) and len(value)<8*1024*1024:media.append(value)
      text=re.sub(r'<(environment_context|external_codex_apps_open_page)\b[^>]*>.*?</\1>', '', text, flags=re.S).strip()
     elif t in ['function_call','custom_tool_call']:role='tool';text='调用 '+str(p.get('name','tool'))
     elif t in ['function_call_output','custom_tool_call_output']:role='tool';text=clean(p.get('output'))
    if kind=='token_usage_record':
     modern_usage=True;u=p.get('thread_token_usage') or {};usage={'input':u.get('input_tokens'),'output':u.get('output_tokens'),'cached':u.get('cached_input_tokens'),'semantics':'includes-cache'}
    if kind=='event_msg' and p.get('type')=='token_count' and not modern_usage:
     u=(p.get('info') or {}).get('total_token_usage') or {};usage={'input':u.get('input_tokens'),'output':u.get('output_tokens'),'cached':u.get('cached_input_tokens'),'semantics':'includes-cache'}
    attachment_ids=list(dict.fromkeys(re.findall(r'/uploads/([a-f0-9-]{36})/(?:media/|content)','\n'.join([text,*media])))) if role=='user' else []
    if role=='user':text,media=visible_user_media(text,media)
    text=display_text(text,role,bool(media),photo_names(media,text))
    if text or media:events.append(dict(id=p.get('id') or str(index),role=role,text=text,media=media,attachmentIds=attachment_ids,phase=p.get('channel'),turnId=(p.get('internal_chat_message_metadata_passthrough') or {}).get('turn_id'),time=ms(d.get('timestamp'))))
 elif agent=='hermes':
  with db(HOME/'.hermes/state.db') as c:
   row=c.execute('SELECT id,title,cwd,git_repo_root,git_branch,model,started_at,last_activity_at,archived,input_tokens,output_tokens,cache_read_tokens FROM sessions WHERE id=? AND hidden=0',(native,)).fetchone()
   if not row:raise ValueError('会话不存在')
   r=dict(row);result=summary('Hermes',r);usage={'input':r['input_tokens'],'output':r['output_tokens'],'cached':r['cache_read_tokens'],'semantics':'provider-reported'}
   for row in hermes_display_rows(c,native):
    r=dict(row);content=r['content'];media=[]
    if hermes_internal_message(content,r.get('display_kind'),r.get('_compressed_summary')):continue
    projected_role,content,background=hermes_message(content,r['role'],r.get('display_kind'))
    if background:
     followup=background.pop('followup','')
     events.extend(hermes_background_events(background,content,r['id'],ms(r['timestamp'])))
     if not followup:continue
     projected_role,content='user',followup
    r['role']=projected_role
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
    if r['role']=='user' and isinstance(content,str):
     # Hermes persists uploaded photos as local @image references.
     image_root=(HOME/'.hermes/images').resolve()
     def photo_ref(match):
      path=pathlib.Path(match[1])
      try:
       if is_relative_to(path.resolve(), image_root) and path.is_file() and path.suffix.lower() in {'.png','.jpg','.jpeg','.gif','.webp'}:
        media.append(str(path));return ''
      except OSError:pass
      return match[0]
     content=re.sub(r'(?m)^@image:([^\n]+)\n?\[screenshot\][ \t]*$',photo_ref,content)
    if r['role']=='assistant' and isinstance(content,str):
     def assistant_media(match):
      value=match[1].strip().strip('\"')
      if pathlib.Path(value).is_absolute() and pathlib.Path(value).suffix.lower() in {'.png','.jpg','.jpeg','.gif','.webp','.mp4','.mov','.m4v','.webm'}:
       media.append(value);return ''
      return match[0]
     content=re.sub(r'(?m)^MEDIA:[ \t]*([^\r\n]+)$',assistant_media,content)
    text=clean(content) or ('工具 '+str(r['tool_name']) if r['tool_name'] else '')
    text=display_text(text,r['role'],bool(media),photo_names(media,text))
    if text.strip() or media:events.append(dict(id=str(r['id']),role=r['role'],text=text,media=media,phase='commentary' if r.get('tool_calls') else None,time=ms(r['timestamp'])))
    calls=r.get('tool_calls')
    try:calls=json.loads(calls) if isinstance(calls,str) else calls
    except:calls=[]
    for call in calls if isinstance(calls,list) else []:
     f=call.get('function') or {};process.start(call.get('id') or call.get('call_id'),f.get('name','工具'),f.get('arguments',''),ms(r['timestamp']),str(r['id'])+':'+str(call.get('id')))
 else:raise ValueError('未知 Agent')
 if agent=='codex':events=group_generated_images(events)
 result.update(**(dict(events=events) if options.get('all') else history_page(events,options.get('before'))),usage=usage,latestProcessTurnId=process.turn)
print(json.dumps(result,ensure_ascii=False))
