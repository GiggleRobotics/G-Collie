"""Isolated native rollout -> full history/pagination display regression."""
import importlib.util
import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('display', ROOT / 'message_display.py')
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)
RULES = '# AGENTS.md instructions for /home/test/project\n\n<INSTRUCTIONS>\n# 项目规则\n保持数据\n</INSTRUCTIONS>'

class CodexContextTests(unittest.TestCase):
    def test_exact_envelope_only_and_keep_extra_human_text(self):
        self.assertEqual(display.codex_user_text(RULES), '')
        self.assertEqual(display.codex_user_text(RULES + '\n\n继续修复'), '继续修复')
        self.assertEqual(display.codex_user_text(RULES.replace('\n', '\r\n')), '')
        for text in ['请阅读 AGENTS.md', '举例：\n' + RULES, '```\n' + RULES + '\n```',
                     RULES.replace('</INSTRUCTIONS>', ''), RULES.replace('/home/test/project', '普通标题'),
                     '# AGENTS.md instructions for /home/test/project\n普通正文']:
            self.assertEqual(display.codex_user_text(text), text)

    def test_upload_attachment_ids_survive_media_only_native_input(self):
        with tempfile.TemporaryDirectory() as folder:
            home=pathlib.Path(folder)
            session=home/'.codex/sessions/fixture.jsonl'
            session.parent.mkdir(parents=True)
            with sqlite3.connect(home/'.codex/state_5.sqlite') as conn:
                conn.execute('CREATE TABLE threads(id,title,name,cwd,git_branch,model,updated_at_ms,updated_at,archived,rollout_path)')
                conn.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?)',('fixture','fixture',None,'/test',None,None,1,1,0,str(session)))
            first='11111111-1111-4111-8111-111111111111'
            second='22222222-2222-4222-8222-222222222222'
            image_a=f'/home/test/.local/share/g-collie/uploads/{first}/media/image.jpg'
            image_b=f'/home/test/.local/share/g-collie/uploads/{second}/content'
            rows=[]
            for mid,role,content in [
                ('image-url','user',[{'type':'input_image','image_url':{'url':image_a}}]),
                ('local-path','user',[{'type':'local_image','path':image_b}]),
                ('mixed','user',[{'type':'input_text','text':image_a},{'type':'input_image','image_url':image_a},{'type':'localImage','path':image_b}]),
                ('assistant','assistant',[{'type':'output_text','text':image_a}]),
            ]:
                rows.append({'type':'response_item','timestamp':'2026-11-15T01:00:00Z','payload':{'type':'message','role':role,'id':mid,'content':content}})
            session.write_text('\n'.join(json.dumps(row) for row in rows))
            env=dict(os.environ,HOME=str(home),GCOLLIE_DATA_DIR=str(home/'data'))
            detail=json.loads(subprocess.check_output(['python3',str(ROOT/'read-local.py'),'detail','codex:fixture','{"all":true}'],env=env,text=True))
            events={e['id']:e for e in detail['events']}
            self.assertEqual(events['image-url']['attachmentIds'],[first])
            self.assertEqual(events['local-path']['attachmentIds'],[second])
            self.assertEqual(events['mixed']['attachmentIds'],[first,second])
            self.assertEqual(events['assistant']['attachmentIds'],[])
            self.assertFalse(any('requestId' in event for event in events.values()))

    def test_rollout_projection_preserves_human_assistant_media_and_pages(self):
        with tempfile.TemporaryDirectory() as folder:
            home = pathlib.Path(folder)
            session = home / '.codex/sessions/fixture.jsonl'
            session.parent.mkdir(parents=True)
            with sqlite3.connect(home / '.codex/state_5.sqlite') as conn:
                conn.execute('CREATE TABLE threads(id,title,name,cwd,git_branch,model,updated_at_ms,updated_at,archived,rollout_path)')
                conn.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?)', ('fixture','fixture',None,'/test',None,None,1,1,0,str(session)))
            rows = []
            def add(mid, text, role='user', media=False):
                content = [{'type':'input_text' if role == 'user' else 'output_text', 'text':text}]
                if media:content.append({'type':'input_image','image_url':'data:image/png;base64,aW1hZ2U='})
                rows.append({'type':'response_item','timestamp':'2026-11-15T01:00:00Z','payload':{'type':'message','role':role,'id':mid,'content':content}})
            for i in range(205):
                add('rules'+str(i), RULES + ('\n<environment_context>\n  <cwd>/test</cwd>\n</environment_context>' if i % 2 else ''))
                add('normal'+str(i), '正常消息 '+str(i))
            add('assistant', RULES, 'assistant')
            add('quote', '用户引用：\n'+RULES)
            add('human', RULES + '\n\n继续修复')
            add('photo', RULES, media=True)
            add('long', RULES.replace('保持数据', '规则'*16000) + '\n\n长规则后的用户正文')
            session.write_text('\n'.join(json.dumps(row,ensure_ascii=False) for row in rows))
            env = dict(os.environ, HOME=str(home), GCOLLIE_DATA_DIR=str(home/'data'))
            def read(options):
                return json.loads(subprocess.check_output(['python3',str(ROOT/'read-local.py'),'detail','codex:fixture',json.dumps(options)],env=env,text=True))
            full = read({'all':True})['events']
            by_id = {e['id']:e for e in full}
            self.assertEqual(len(full),210)
            self.assertFalse(any(key.startswith('rules') for key in by_id))
            self.assertEqual(by_id['assistant']['text'],RULES)
            self.assertEqual(by_id['quote']['text'],'用户引用：\n'+RULES)
            self.assertEqual(by_id['human']['text'],'继续修复')
            self.assertEqual(by_id['long']['text'],'长规则后的用户正文')
            self.assertEqual(by_id['photo']['text'],'')
            self.assertEqual(by_id['photo']['media'],['data:image/png;base64,aW1hZ2U='])
            latest = read({})
            self.assertTrue(latest['hasMoreHistory'])
            older = read({'before':latest['historyCursor']})
            self.assertFalse(older['hasMoreHistory'])
            self.assertEqual(older['events']+latest['events'],full)

unittest.main()
