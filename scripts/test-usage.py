import unittest,tempfile,pathlib,json,importlib.util,os,sqlite3
spec=importlib.util.spec_from_file_location('usage',pathlib.Path(__file__).with_name('read-usage.py'));u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
class UsageTests(unittest.TestCase):
 def scan(self,items):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'log.jsonl';p.write_text('\n'.join(json.dumps(x) for x in items)+'\n');return u.scan(p,'s')
 def record(self,kind,p,t='2026-10-18T04:00:00Z'):return dict(type=kind,payload=p,timestamp=t)
 def test_modern_dedup_and_legacy_mirror(self):
  rec=self.record('token_usage_record',dict(response_id='r1',usage=dict(input_tokens=100,cached_input_tokens=80,output_tokens=20),thread_token_usage=dict(input_tokens=100,output_tokens=20)))
  data=self.scan([rec,rec,self.record('event_msg',dict(type='token_count',info=dict(total_token_usage=dict(input_tokens=100,output_tokens=20))))])
  self.assertEqual(len(data['events']),1);self.assertEqual(u.finish(data['events'][0]['usage'])['total'],120)
 def test_legacy_snapshot_is_delta(self):
  def r(i,o):return self.record('event_msg',dict(type='token_count',info=dict(total_token_usage=dict(input_tokens=i,output_tokens=o))))
  d=self.scan([r(100,20),r(100,20),r(150,30)]);total=u.blank()
  for e in d['events']:u.add(total,e['usage'])
  self.assertEqual(u.finish(total)['total'],180);self.assertEqual(total['requests'],2)
 def test_missing_history_not_assigned_to_today(self):
  d=self.scan([self.record('token_usage_record',dict(response_id='r',usage=dict(input_tokens=20,output_tokens=5),thread_token_usage=dict(input_tokens=100,output_tokens=30)))])
  self.assertEqual(d['events'][1]['day'],None);self.assertEqual(u.finish(d['events'][1]['usage'])['total'],105)
 def test_hermes_cache_is_added_once(self):
  v=u.finish(u.metrics(dict(input_tokens=10,output_tokens=20,cache_read_tokens=70,reasoning_tokens=5,api_call_count=2),True))
  self.assertEqual(v['input'],80);self.assertEqual(v['total'],100);self.assertEqual(v['reasoning'],5)
 def test_local_timezone_date(self):
  self.assertEqual(u.day('not-a-time'),None)
 def test_report_db_fallback_and_hermes_baseline(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d)/'home';data=pathlib.Path(d)/'data';(home/'.codex').mkdir(parents=True);(home/'.hermes').mkdir()
   c=sqlite3.connect(home/'.codex/state_1.sqlite');c.execute('CREATE TABLE threads(id,title,name,cwd,model,rollout_path,tokens_used,created_at)');c.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?)',('s','A',None,'','gpt',str(home/'.codex/sessions/missing.jsonl'),123,1));c.commit();c.close()
   c=sqlite3.connect(home/'.hermes/state.db');c.execute('CREATE TABLE sessions(id,title,cwd,git_repo_root,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,reasoning_tokens,api_call_count,estimated_cost_usd,actual_cost_usd,cost_status)');c.execute('INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',('h','H','','','deepseek-flash',10,5,50,0,2,1,.01,None,'estimated'));c.commit()
   oldhome,olddata=u.HOME,u.DATA;u.HOME,u.DATA=home,data
   try:
    a=u.report();self.assertEqual(a['agents']['Codex']['total']['total'],0);self.assertEqual(a['agents']['Codex']['total']['unclassified'],123);self.assertEqual(a['agents']['Codex']['coverage']['undated']['unclassified'],123)
    self.assertEqual(a['agents']['Hermes']['total']['total'],65);self.assertEqual(a['agents']['Hermes']['today']['total'],0)
    c.execute('UPDATE sessions SET input_tokens=20,output_tokens=8,cache_read_tokens=60,api_call_count=2');c.commit();b=u.report();self.assertEqual(b['agents']['Hermes']['today']['total'],23)
    self.assertEqual(u.report()['agents']['Hermes']['today']['total'],23)
   finally:u.HOME,u.DATA=oldhome,olddata;c.close()
class ClaudeUsageTests(unittest.TestCase):
 def row(self,id='msg1',output=5,**extra):
  return dict(type='assistant',timestamp='2026-10-23T04:00:00Z',cwd='/work/project',message=dict(id=id,model='deepseek-flash',usage=dict(input_tokens=10,cache_read_input_tokens=20,cache_creation_input_tokens=30,output_tokens=output)),**extra)
 def test_streaming_duplicates_count_once_and_include_cache(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'s.jsonl';p.write_text('\n'.join(json.dumps(r) for r in [self.row(output=1),self.row(),self.row(),dict(type='progress'),dict(type='user',message=dict(content='private prompt'))])+'\n{partial')
   data=u.scan_claude(p);self.assertEqual(len(data['events']),1);v=data['events'][0]['usage']
   self.assertEqual(v['input'],60);self.assertEqual(v['output'],5);self.assertEqual(v['requests'],1);self.assertEqual(v['cacheWrite'],30);self.assertEqual(data['badLines'],1)
   self.assertNotIn('private prompt',json.dumps(data['events']))
 def test_report_includes_subagents_dates_project_and_clickable_session(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d)/'home';data=pathlib.Path(d)/'data';root=home/'.claude/projects/proj';root.mkdir(parents=True)
   p=root/'session.jsonl';p.write_text(json.dumps(self.row())+'\n')
   sub=root/'session/subagents';sub.mkdir(parents=True);(sub/'agent.jsonl').write_text(json.dumps(self.row(id='child',output=7))+'\n')
   oldhome,olddata=u.HOME,u.DATA;u.HOME,u.DATA=home,data
   try:
    a=u.report()['agents']['Claude Code'];self.assertEqual(a['total']['total'],132);self.assertEqual(a['total']['requests'],2)
    self.assertEqual(a['sessions'][0]['id'],'claude:session');self.assertEqual(a['projects'][0]['path'],'/work/project');self.assertEqual(a['daily'][0]['usage']['total'],132)
    self.assertEqual(u.report()['agents']['Claude Code']['total'],a['total'])
    p.write_text(p.read_text()+json.dumps(self.row(id='next',output=2))+'\n');self.assertEqual(u.report()['agents']['Claude Code']['total']['total'],194)
   finally:u.HOME,u.DATA=oldhome,olddata
if __name__=='__main__':unittest.main()
