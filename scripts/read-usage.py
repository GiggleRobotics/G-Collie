"""Private local usage index. Only exports allowlisted counters, never message content/auth."""
import os,sys,json,pathlib,sqlite3,datetime,hashlib
from collections import defaultdict
HOME=pathlib.Path(os.environ.get('GCOLLIE_USAGE_HOME',str(pathlib.Path.home())))
DATA=pathlib.Path(os.environ.get('GCOLLIE_DATA_DIR','.data'))
FIELDS=['input','output','cached','cacheWrite','reasoning','requests','unclassified']
def blank():return {k:0 for k in FIELDS}
def add(a,b):
 for k in FIELDS:a[k]+=b.get(k,0) or 0
 return a
def metrics(u,hermes=False):
 n=lambda k:max(0,u.get(k) or 0)
 return dict(input=n('input_tokens')+(n('cache_read_tokens')+n('cache_write_tokens') if hermes else 0),output=n('output_tokens'),cached=n('cache_read_tokens' if hermes else 'cached_input_tokens'),cacheWrite=n('cache_write_tokens' if hermes else 'cache_write_input_tokens'),reasoning=n('reasoning_tokens' if hermes else 'reasoning_output_tokens'),unclassified=0,requests=n('api_call_count') if hermes else 1)
def finish(u):return dict(u,total=u['input']+u['output'],cacheRate=(u['cached']/u['input'] if u['input'] else None))
def day(t):
 try:return datetime.datetime.fromisoformat(t.replace('Z','+00:00')).astimezone().date().isoformat()
 except:return None
def db(path):
 c=sqlite3.connect(path.resolve().as_uri()+'?mode=ro',uri=True,timeout=3);c.row_factory=sqlite3.Row;c.execute('PRAGMA query_only=ON');return c

def scan(path,native):
 events=[];legacy=[];modern=False;last=blank();latest_total=blank();limits=None;seen=set();model='未知';bad=0
 with path.open('rb') as f:
  for line in f:
   if not any(v in line[:250] for v in [b'"token_usage_record"',b'"event_msg"',b'"turn_context"']):continue
   if b'"token_usage_record"' not in line[:250] and b'"turn_context"' not in line[:250] and b'"token_count"' not in line[:600]:continue
   try:d=json.loads(line)
   except:bad+=1;continue
   p=d.get('payload') or {};kind=d.get('type');stamp=d.get('timestamp','')
   if kind=='turn_context':model=p.get('model') or model;continue
   if kind=='token_usage_record':
    modern=True
    key=p.get('response_id') or hashlib.sha256(line).hexdigest()
    if key in seen:continue
    seen.add(key);u=metrics(p.get('usage') or {})
    events.append(dict(key=key,day=day(stamp),model=model,usage=u))
    t=metrics(p.get('thread_token_usage') or {});t['requests']=0
    latest_total=t
   elif kind=='event_msg' and p.get('type')=='token_count':
    if p.get('rate_limits'):limits=dict(data=p['rate_limits'],at=stamp)
    if modern:continue
    raw=(p.get('info') or {}).get('total_token_usage')
    if not raw:continue
    u=metrics(raw);u['requests']=0
    # Cumulative snapshots: unchanged repeats must not count another request.
    if u['input']<last['input'] or u['output']<last['output']:
     delta=metrics((p.get('info') or {}).get('last_token_usage') or {});delta['requests']=0
    else:delta={k:max(0,u[k]-last[k]) for k in FIELDS}
    last=u
    if delta['input'] or delta['output']:
     delta['requests']=1;legacy.append(dict(key=None,day=day(stamp),model=model,usage=delta))
 if not modern:events=legacy
 # A cumulative total can include history absent from response records (migration/fork).
 # Preserve it as undated rather than falsely assigning it to the first observed day.
 total=blank()
 for e in events:add(total,e['usage'])
 undated=blank()
 if modern:
  for k in FIELDS:
   if k!='requests':undated[k]=max(0,latest_total[k]-total[k])
 if undated['input'] or undated['output']:events.append(dict(key=None,day=None,model='历史未分模型',usage=undated))
 return dict(events=events,limits=limits,badLines=bad,modern=modern)

def project_for(agent,r,state):
 if agent=='Codex':
  if r['id'] in state.get('projectless-thread-ids',[]):return None
  p=state.get('local-projects',{}).get(state.get('thread-project-assignments',{}).get(r['id'],{}).get('projectId'))
  if p and p.get('rootPaths'):return dict(path=p['rootPaths'][0],name=p.get('name') or pathlib.Path(p['rootPaths'][0]).name)
 cwd=r.get('cwd') or r.get('git_repo_root') or ''
 matches=[(root,p) for p in state.get('local-projects',{}).values() for root in p.get('rootPaths',[]) if cwd and (pathlib.Path(cwd)==pathlib.Path(root) or pathlib.Path(cwd).is_relative_to(pathlib.Path(root)))]
 if matches:
  root,p=max(matches,key=lambda x:len(x[0]));return dict(path=root,name=p.get('name') or pathlib.Path(root).name)
 if agent=='Hermes' and r.get('git_repo_root'):return dict(path=r['git_repo_root'],name=pathlib.Path(r['git_repo_root']).name)
 return None

def report():
 DATA.mkdir(parents=True,exist_ok=True);cache_path=DATA/'usage-index.json'
 try:cache=json.loads(cache_path.read_text())
 except:cache={}
 if cache.get('version')!=3:cache=dict(version=3,files={},hermes={},trackingSince=datetime.datetime.now().astimezone().isoformat(),hermesDays={})
 try:state=json.loads((HOME/'.codex/.codex-global-state.json').read_text())
 except:state={}
 result=dict(generatedAt=datetime.datetime.now().astimezone().isoformat(),timezone=str(datetime.datetime.now().astimezone().tzinfo),trackingSince=cache['trackingSince'],agents={},warnings=[])
 agents={a:dict(total=blank(),days={},sessions=[],projects={},models={},coverage=dict(sessions=0,withUsage=0,missingFiles=0,undated=blank())) for a in ['Codex','Hermes']}
 global_seen=set();latest_limits=None;newfiles={}
 def ingest(agent,r,events,extra=None):
  a=agents[agent];a['coverage']['sessions']+=1;p=project_for(agent,r,state);total=blank();modelTotals={}
  for e in events:
   key=e.get('key')
   if key and key in global_seen:continue
   if key:global_seen.add(key)
   u=e['usage'];add(total,u);date=e.get('day')
   if date:add(a['days'].setdefault(date,blank()),u)
   else:add(a['coverage']['undated'],u)
   add(a['models'].setdefault(e.get('model') or '未知',blank()),u)
  add(a['total'],total)
  if finish(total)['total'] or total.get('unclassified'):a['coverage']['withUsage']+=1
  pk=p['path'] if p else ''
  proj=a['projects'].setdefault(pk,dict(name=p['name'] if p else '未关联项目',path=pk,usage=blank(),sessions=0));add(proj['usage'],total);proj['sessions']+=1
  a['sessions'].append(dict(id=agent.lower()+':'+r['id'],title=(r.get('name') or r.get('title') or '未命名会话')[:160],project=p['name'] if p else '无项目',model=r.get('model'),usage=finish(total),**(extra or {})))
 try:
  files=list((HOME/'.codex').glob('state_*.sqlite'))
  if not files:raise FileNotFoundError()
  with db(max(files,key=lambda p:p.stat().st_mtime)) as c:
   for row in c.execute('SELECT id,title,name,cwd,model,rollout_path,tokens_used FROM threads ORDER BY created_at,id'):
    r=dict(row);path=pathlib.Path(r['rollout_path'] or '').resolve();allowed=[(HOME/'.codex/sessions').resolve(),(HOME/'.codex/archived_sessions').resolve()]
    try:
     if not any(path.is_relative_to(root) for root in allowed):raise ValueError()
     st=path.stat();signature=[str(path),st.st_size,st.st_mtime_ns];old=cache['files'].get(r['id'])
     data=old['data'] if old and old['signature']==signature else scan(path,r['id'])
     newfiles[r['id']]=dict(signature=signature,data=data)
     if data.get('limits') and (not latest_limits or data['limits']['at']>latest_limits['at']):latest_limits=data['limits']
     ingest('Codex',r,data['events'])
    except (OSError,ValueError):
     agents['Codex']['coverage']['missingFiles']+=1
     u=blank();u['unclassified']=max(0,r.get('tokens_used') or 0)
     ingest('Codex',r,[dict(day=None,model=r.get('model') or '历史未分模型',usage=u)],dict(totalSource='数据库快照（缺少明细）'))
 except Exception:result['warnings'].append('Codex 本地数据库不可读，统计可能不完整')
 cache['files']=newfiles
 try:
  with db(HOME/'.hermes/state.db') as c:
   rows=[dict(r) for r in c.execute('SELECT id,title,cwd,git_repo_root,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,reasoning_tokens,api_call_count,estimated_cost_usd,actual_cost_usd,cost_status FROM sessions')]
   modelrows={}
   try:
    for mr in c.execute('SELECT session_id,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,reasoning_tokens,api_call_count,estimated_cost_usd,actual_cost_usd,cost_status FROM session_model_usage'):
     modelrows.setdefault(mr['session_id'],[]).append(dict(mr))
   except sqlite3.OperationalError:pass
   nowday=datetime.datetime.now().astimezone().date().isoformat();known=cache['hermes'];days=cache['hermesDays']
   estimated=actual=0.;estimated_count=actual_count=unknown_count=0
   for r in rows:
    u=metrics(r,True);previous=known.get(r['id']);events=[]
    if previous:
     delta={k:max(0,u[k]-previous[k]) for k in FIELDS}
     if any(delta.values()):add(days.setdefault(r['id'],{}).setdefault(nowday,blank()),delta)
    known[r['id']]=u
    tracked=blank()
    for date,amount in days.get(r['id'],{}).items():add(tracked,amount);events.append(dict(day=date,model=r.get('model'),usage=amount))
    baseline={k:max(0,u[k]-tracked[k]) for k in FIELDS};events.append(dict(day=None,model=r.get('model'),usage=baseline))
    extra=dict(estimatedCostUSD=r['estimated_cost_usd'] if r['cost_status']=='estimated' else None,actualCostUSD=r['actual_cost_usd'] if r['cost_status']=='actual' else None,costStatus=r['cost_status'] or 'unknown')
    if extra['estimatedCostUSD'] is not None:estimated+=extra['estimatedCostUSD'];estimated_count+=1
    elif extra['actualCostUSD'] is not None:actual+=extra['actualCostUSD'];actual_count+=1
    else:unknown_count+=1
    ingest('Hermes',r,events,extra)
   # Dedicated per-model counters include model switches and auxiliary requests.
   models={}
   for r in rows:
    for mr in modelrows.get(r['id'],[r]):add(models.setdefault(mr.get('model') or '未知',blank()),metrics(mr,True))
   agents['Hermes']['models']=models
   low=high=0.;unknown=[]
   for model,u in models.items():
    if model in ['deepseek-flash','deepseek-v4-flash','deepseek-v4-flash-vision-exp']:rates=(.02,1,4)
    elif model=='deepseek-v4-pro':rates=(.15,4.5,13.5)
    else:unknown.append(model);continue
    price=(u['cached']*rates[0]+max(0,u['input']-u['cached'])*rates[1]+u['output']*rates[2])/1000000
    low+=price;high+=2*price
   agents['Hermes']['costCNY']=dict(low=low,high=high,unknownModels=unknown,pricingDate='2026-10-19',source='https://api-docs.deepseek.com/zh-cn/quick_start/pricing/')
   agents['Hermes']['cost']=dict(estimatedUSD=estimated if estimated_count else None,actualUSD=actual if actual_count else None,estimatedSessions=estimated_count,actualSessions=actual_count,unknownSessions=unknown_count)
 except Exception:result['warnings'].append('Hermes 本地数据库不可读，统计可能不完整')
 today=datetime.datetime.now().astimezone().date();month=today.isoformat()[:7]
 for name,a in agents.items():
  for k in ['total']:a[k]=finish(a[k])
  a['today']=finish(a['days'].get(today.isoformat(),blank()));monthly=blank()
  for date,u in a['days'].items():
   if date.startswith(month):add(monthly,u)
  a['month']=finish(monthly)
  a['daily']=[dict(date=d,usage=finish(u)) for d,u in sorted(a.pop('days').items())]
  months={}
  for item in a['daily']:add(months.setdefault(item['date'][:7],blank()),item['usage'])
  a['monthly']=[dict(month=m,usage=finish(u)) for m,u in sorted(months.items())]
  a['projects']=[dict(p,usage=finish(p['usage'])) for p in a['projects'].values()];a['projects'].sort(key=lambda p:p['usage']['total'],reverse=True)
  a['models']=[dict(model=m,usage=finish(u)) for m,u in a['models'].items()];a['models'].sort(key=lambda p:p['usage']['total'],reverse=True)
  a['sessions'].sort(key=lambda s:s['usage']['total'],reverse=True)
  a['coverage']['undated']=finish(a['coverage']['undated'])
 result['agents']=agents;result['logLimits']=latest_limits
 tmp=cache_path.with_suffix('.tmp');tmp.write_text(json.dumps(cache,separators=(',',':')));tmp.chmod(0o600);tmp.replace(cache_path)
 return result
if __name__=='__main__':print(json.dumps(report(),ensure_ascii=False,separators=(',',':')))
