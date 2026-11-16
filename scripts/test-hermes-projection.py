"""Isolated native SQLite -> read-local projection; never opens real sessions."""
import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
HEADER = ('[IMPORTANT: 2 background processes completed. Treat these results as one batch '
          'and give one consolidated response; preserve failures and actionable results.]')

def completion(pid, code, output):
    kind = 'completed normally' if code == 0 else 'exited'
    return f'[IMPORTANT: Background process proc_{pid} {kind} (exit code {code}).\nCommand: echo {pid}\nOutput:\n{output}]'

BATCH = HEADER + '\n\n' + completion('a', 0, 'ok ]\n\nmore') + '\n\n' + completion('b', -15, 'failure')
WATCH = '[IMPORTANT: Background process proc_a matched watch pattern "ready".\nCommand: echo a\nMatched output:\nready\n(2 earlier matches were suppressed by rate limit)]'

class HermesProjectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name)
        (self.home / '.hermes').mkdir()
        self.db = sqlite3.connect(self.home / '.hermes/state.db')
        self.db.executescript('''
          CREATE TABLE sessions(id TEXT,title TEXT,cwd TEXT,git_repo_root TEXT,git_branch TEXT,model TEXT,started_at INT,last_activity_at INT,archived INT,input_tokens INT,output_tokens INT,cache_read_tokens INT,hidden INT);
          INSERT INTO sessions VALUES('fixture','isolated','','','','',1,2,0,0,0,0,0);
          CREATE TABLE messages(id INTEGER PRIMARY KEY,session_id TEXT,role TEXT,content TEXT,tool_name TEXT,tool_calls TEXT,tool_call_id TEXT,display_kind TEXT,_compressed_summary INT,timestamp INT);
        ''')
        for i in range(205):
            self.add(i + 1, 'user', f'normal {i}')
        self.add(300, 'user', BATCH, 'process_complete')
        self.add(301, 'user', WATCH)
        self.add(302, 'user', '用户引用：' + BATCH)
        self.add(303, 'assistant', BATCH)
        self.add(304, 'user', BATCH.replace('2 background', '3 background'), 'process_complete')
        self.add(305, 'user', completion('single', 2, 'error') + '\n\n继续')
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def add(self, mid, role, text, kind=None):
        self.db.execute('INSERT INTO messages(id,session_id,role,content,tool_name,tool_calls,tool_call_id,display_kind,_compressed_summary,timestamp) VALUES(?,?,?,?,NULL,NULL,NULL,?,0,?)', (mid, 'fixture', role, text, kind, mid))

    def read(self, options=None):
        env = dict(os.environ, HOME=str(self.home), GCOLLIE_DATA_DIR=str(self.home / 'data'))
        return json.loads(subprocess.check_output(['python3', str(ROOT / 'read-local.py'), 'detail', 'hermes:fixture', json.dumps(options or {})], env=env, text=True))

    def test_native_history_projects_batch_watch_and_preserves_human_content(self):
        events = self.read({'all': True})['events']
        rows = {e['id']: e for e in events}
        self.assertNotIn('300', rows)
        self.assertNotIn('301', rows)
        self.assertEqual(rows['background:300:0']['text'], 'ok ]\n\nmore')
        self.assertEqual(rows['background:300:0']['status'], 'completed')
        self.assertEqual(rows['background:300:1']['status'], 'failed')
        self.assertEqual(rows['background:300:1']['text'], 'failure')
        self.assertEqual(rows['background:300:1']['input'], 'echo b')
        self.assertEqual(rows['background:300:1']['time'], 300000)
        self.assertEqual(rows['background:301']['status'], 'pending')
        self.assertIn('命中观察规则：ready', rows['background:301']['text'])
        self.assertIn('suppressed', rows['background:301']['text'])
        self.assertEqual(rows['302']['text'], '用户引用：' + BATCH)
        self.assertEqual(rows['303']['role'], 'assistant')
        self.assertEqual(rows['303']['text'], BATCH)
        self.assertEqual(rows['304']['text'], BATCH.replace('2 background', '3 background'))
        self.assertEqual(rows['305']['text'], '继续')
        self.assertEqual(rows['background:305']['status'], 'failed')
        self.assertEqual([e['id'] for e in events[-8:]], ['background:300:0','background:300:1','background:301','302','303','304','background:305','305'])
        self.assertEqual(self.db.execute('SELECT content FROM messages WHERE id=300').fetchone()[0], BATCH)

    def test_compaction_generations_collapse_by_native_identity_not_text(self):
        self.db.executescript("ALTER TABLE messages ADD COLUMN active INT DEFAULT 1; ALTER TABLE messages ADD COLUMN compacted INT DEFAULT 0; ALTER TABLE messages ADD COLUMN display_identity BLOB; ALTER TABLE messages ADD COLUMN display_order INT;")
        self.add(500, 'user', 'same deliberate input')
        self.add(501, 'assistant', 'first reply')
        self.add(502, 'user', 'same deliberate input')
        self.add(503, 'assistant', 'second reply')
        # Compaction copies the protected tail to larger IDs with the original timestamp.
        self.db.execute("UPDATE messages SET active=0,compacted=1,display_identity=X'01',display_order=500 WHERE id=500")
        self.db.execute("INSERT INTO messages SELECT 600,session_id,role,content,tool_name,tool_calls,tool_call_id,display_kind,_compressed_summary,timestamp,1,0,X'01',500 FROM messages WHERE id=500")
        self.db.execute("UPDATE messages SET active=0,compacted=0 WHERE id=503")
        self.db.commit()
        events=self.read({'all': True})['events']
        rows=[e for e in events if e['text']=='same deliberate input']
        self.assertEqual([e['id'] for e in rows], ['500','502'])
        self.assertLess(events.index(rows[0]),next(i for i,e in enumerate(events) if e['id']=='501'))
        self.assertNotIn('503',[e['id'] for e in events])
        self.assertEqual(events,self.read({'all': True})['events'])
        self.db.execute("UPDATE messages SET active=0,compacted=1 WHERE id=600")
        self.db.execute("INSERT INTO messages SELECT 700,session_id,role,content,tool_name,tool_calls,tool_call_id,display_kind,_compressed_summary,timestamp,1,0,display_identity,display_order FROM messages WHERE id=600")
        self.db.commit()
        self.assertEqual(events,self.read({'all': True})['events'])

    def test_legacy_generation_identity_includes_timestamp_and_tool_linkage(self):
        images='[{"type":"image_url","image_url":"/fixture/a.png"},{"type":"image_url","image_url":"/fixture/b.png"}]'
        self.add(500,'user',images)
        self.add(501,'assistant','same text')
        self.add(502,'user',images)
        self.add(503,'assistant','same text')
        self.db.execute("INSERT INTO messages SELECT 600,session_id,role,content,tool_name,tool_calls,tool_call_id,display_kind,_compressed_summary,timestamp FROM messages WHERE id=500")
        self.db.commit()
        events=[e for e in self.read({'all': True})['events'] if not e['id'].startswith('background:') and int(e['id'])>=500]
        self.assertEqual([e['id'] for e in events],['500','501','502','503'])
        self.assertEqual(len(events[0]['media']),2)
        self.assertEqual(len(events[2]['media']),2)
        self.assertEqual([e['text'] for e in events if e['role']=='assistant'],['same text','same text'])

    def test_reload_and_pagination_keep_ids_and_cursor_stable_with_new_tail(self):
        whole = self.read({'all': True})['events']
        latest = self.read()
        self.assertTrue(latest['hasMoreHistory'])
        self.assertEqual(latest, self.read())
        self.add(400, 'assistant', 'new tail')
        self.db.commit()
        earlier = self.read({'before': latest['historyCursor']})
        self.assertFalse(earlier['hasMoreHistory'])
        combined = earlier['events'] + latest['events']
        self.assertEqual(combined, whole)
        self.assertEqual(len({e['id'] for e in combined}), len(combined))

if __name__ == '__main__':
    unittest.main()
