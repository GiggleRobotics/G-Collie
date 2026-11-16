"""Independent read-local + production Web QA, isolated HOME and GET-only fixture API.
Run after npm run build: python3 scripts/hermes-notification-qa.py --serve --port 4397
No production database, agent process, pairing credential or model request is used.
"""
import argparse, hashlib, json, os, pathlib, sqlite3, subprocess, tempfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

ROOT=pathlib.Path(__file__).resolve().parent.parent
HEAD='[IMPORTANT: 2 background processes completed. Treat these results as one batch and give one consolidated response; preserve failures and actionable results.]'
SUCCESS='[IMPORTANT: Background process proc_qa_ok completed normally (exit code 0).\nCommand: echo QA_SUCCESS\nOutput:\nQA_SUCCESS\nvalue=[safe]\n]'
FAILED='[IMPORTANT: Background process proc_qa_fail exited (exit code 2).\nCommand: echo QA_FAILURE\nOutput:\nQA_FAILURE\n]'
WATCH='[IMPORTANT: Background process proc_qa_watch matched watch pattern "QA_READY".\nCommand: echo QA_READY\nMatched output:\nQA_READY]'
SESSION='hermes:qa-notifications'

def main():
 p=argparse.ArgumentParser();p.add_argument('--serve',action='store_true');p.add_argument('--port',type=int,default=4397);args=p.parse_args()
 with tempfile.TemporaryDirectory(prefix='gcollie-product-qa-') as temp:
  home=pathlib.Path(temp);(home/'.hermes').mkdir()
  db=sqlite3.connect(home/'.hermes/state.db')
  db.execute('CREATE TABLE sessions(id,title,cwd,git_repo_root,git_branch,model,started_at,last_activity_at,archived,input_tokens,output_tokens,cache_read_tokens,hidden)')
  db.execute('INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',('qa-notifications','后台通知独立验收','','','','test',1700000000,1700001000,0,0,0,0,0))
  db.execute('CREATE TABLE messages(id INTEGER PRIMARY KEY,session_id,role,content,tool_name,tool_calls,tool_call_id,display_kind,_compressed_summary,timestamp)')
  messages=[('user','请检查后台任务',None)]
  messages += [('assistant',f'历史记录 {i}',None) for i in range(205)]
  messages += [('user',HEAD+'\n\n'+SUCCESS+'\n\n'+FAILED,'process_complete'),('user',WATCH,None),('assistant','后台任务检查完成；失败结果已保留。',None),('user','引用示例：'+SUCCESS,None),('assistant',SUCCESS,None),('user',HEAD.replace('2 background','3 background')+'\n\n'+SUCCESS+'\n\n'+FAILED,None),('user',SUCCESS+'\n\n继续检查',None)]
  for i,(role,text,kind) in enumerate(messages,1): db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?,?,?,?,?)',(i,'qa-notifications',role,text,None,None,None,kind,0,1700000000+i))
  db.commit();db.close()
  env={**os.environ,'HOME':str(home),'GCOLLIE_DATA_DIR':str(home/'data')}
  def project(options):
   return json.loads(subprocess.check_output(['python3',str(ROOT/'scripts/read-local.py'),'detail',SESSION,json.dumps(options)],cwd=ROOT,env=env,text=True))
  detail=project({'all':True});events=detail['events'];first=project({});older=project({'before':first['historyCursor']})
  assert older['events']+first['events']==events,'pagination changed order/content'
  assert project({'all':True})==detail,'projection IDs/content unstable'
  assert len({e['id'] for e in events})==len(events),'duplicate event IDs'
  batch=[e for e in events if e['role']=='tool' and 'QA_SUCCESS' in e.get('text','')]
  assert batch,'batch success missing from tools'
  assert any(e['role']=='tool' and e.get('status')=='failed' and 'QA_FAILURE' in e.get('text','') for e in events),'failed child missing'
  assert any(e['role']=='tool' and 'QA_READY' in e.get('text','') for e in events),'watch missing from tools'
  assert not any(e['role']=='user' and e.get('text') in (HEAD+'\n\n'+SUCCESS+'\n\n'+FAILED,WATCH) for e in events),'internal user bubble remains'
  assert any(e['role']=='user' and e.get('text','').startswith('引用示例：') for e in events),'user example lost'
  assert any(e['role']=='assistant' and e.get('text')==SUCCESS for e in events),'assistant content lost'
  assert any(e['role']=='user' and e.get('text','').startswith('[IMPORTANT: 3 background') for e in events),'invalid batch wrongly consumed'
  assert any(e['role']=='user' and e.get('text')=='继续检查' for e in events),'followup lost'
  print(json.dumps({'result':'PASS','events':len(events),'pageEvents':len(first['events']),'olderEvents':len(older['events']),'stable':True,'distIndexSha256':hashlib.sha256((ROOT/'dist/index.html').read_bytes()).hexdigest()},ensure_ascii=False),flush=True)
  if not args.serve:return
  # The UI fixture omits deliberate negative-envelope examples to make absence
  # of leaked transport text visually inspectable; full-chain assertions above
  # explicitly prove those examples are retained.
  visible=[e for e in events if e['role']=='tool' or e.get('text') in ('请检查后台任务','后台任务检查完成；失败结果已保留。','继续检查')]
  fixture={**detail,'events':visible,'historyCursor':None,'hasMoreHistory':False,'desktopLive':True,'desktopControl':False,'readOnly':True,'status':'idle'}
  class Handler(SimpleHTTPRequestHandler):
   def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT/'dist'),**kw)
   def do_POST(self):self.send_error(405,'Read-only fixture; writes disabled')
   def do_GET(self):
    route=unquote(urlparse(self.path).path)
    if route.startswith('/api/'):
     if route=='/api/auth/status':value={'paired':True,'device':{'role':'view','name':'isolated QA'}}
     elif route=='/api/local':value={'sessions':[fixture],'projects':[],'warnings':[]}
     elif route=='/api/local/'+SESSION:value=fixture
     else:self.send_error(404,'No fixture for this endpoint');return
     payload=json.dumps(value,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(payload);return
    super().do_GET()
   def log_message(self,*a):pass
  print(f'http://127.0.0.1:{args.port}/?session={SESSION}',flush=True)
  ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
if __name__=='__main__':main()
