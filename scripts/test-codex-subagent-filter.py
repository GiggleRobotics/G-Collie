"""Temporary-HOME native database projection; never edits real Codex data."""
import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('read-local.py')


class SubagentProjectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = pathlib.Path(self.temp.name)
        (self.home / '.codex/sessions').mkdir(parents=True)
        self.connection = sqlite3.connect(self.home / '.codex/state_5.sqlite')
        self.addCleanup(self.connection.close)

    def schema(self, metadata=True):
        self.metadata = metadata
        self.connection.execute('CREATE TABLE threads(id,title,name,cwd,git_branch,model,updated_at_ms,updated_at,archived,rollout_path' + (',source' if metadata == 'source-only' else ',source,thread_source' if metadata else '') + ')')

    def add(self, id, source='vscode', thread_source='user', updated=1, header=None):
        path = self.home / '.codex/sessions' / (id + '.jsonl')
        # Every fixture intentionally shares inherited text and has no name.
        rows = [{'type': 'session_meta', 'payload': header or {'id': id, 'source': source, 'thread_source': thread_source}},
                {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': '复制的上下文'}]}}]
        path.write_text('\n'.join(json.dumps(row) for row in rows))
        values = [id, '', None, '/fixture', None, None, updated * 1000, updated, 0, str(path)]
        if self.metadata:
            values += [json.dumps(source) if isinstance(source, dict) else source]
            if self.metadata != 'source-only':
                values.append(thread_source)
        self.connection.execute('INSERT INTO threads VALUES(' + ','.join('?' for _ in values) + ')', values)
        self.connection.commit()

    def read(self, mode='list', id=None):
        env = dict(os.environ, HOME=str(self.home), GCOLLIE_DATA_DIR=str(self.home / 'data'))
        args = ['python3', str(SCRIPT), mode] + (['codex:' + id, '{"all":true}'] if id else [])
        return subprocess.run(args, env=env, capture_output=True, text=True)

    def test_explicit_sources_hidden_but_user_forks_preserved(self):
        self.schema()
        self.add('worker', {'subagent': {'thread_spawn': {'parent_thread_id': 'parent'}}}, 'subagent')
        self.add('legacyworker', {'subagent': 'review'}, None)
        self.add('declaredworker', 'vscode', 'subagent')
        self.add('stringworker', 'subagent', None)
        self.add('fork', header={'id': 'fork', 'forked_from_id': 'parent', 'parent_thread_id': 'parent', 'source': 'vscode', 'thread_source': 'user'})
        self.add('created', 'vscode', 'agent_created_thread')
        self.add('handoff', 'vscode', 'chatgpt_handoff')
        self.add('cli', 'cli', 'user')
        self.add('exec', 'exec', 'user')
        self.add('unknown', '{malformed', None)
        result = json.loads(self.read().stdout)
        self.assertEqual({s['nativeId'] for s in result['sessions']}, {'fork', 'created', 'handoff', 'cli', 'exec', 'unknown'})
        for id in ['worker', 'legacyworker', 'declaredworker', 'stringworker']:
            self.assertNotEqual(self.read('detail', id).returncode, 0)
        fork = self.read('detail', 'fork')
        self.assertEqual(fork.returncode, 0, fork.stderr)
        self.assertEqual(json.loads(fork.stdout)['events'][0]['text'], '复制的上下文')

    def test_filter_precedes_limit(self):
        self.schema()
        self.add('real', updated=1)
        for i in range(501):
            self.add('worker' + str(i), {'subagent': {'thread_spawn': {}}}, 'subagent', updated=i + 2)
        self.assertEqual([s['nativeId'] for s in json.loads(self.read().stdout)['sessions']], ['real'])

    def test_old_schema_metadata_header_and_ordinary_fork(self):
        self.schema(metadata=False)
        self.add('worker', header={'id': 'worker', 'source': {'subagent': {'thread_spawn': {'parent_thread_id': 'parent'}}}})
        self.add('fork', header={'id': 'fork', 'forked_from_id': 'parent', 'source': 'vscode'})
        self.add('plain')
        self.assertEqual({s['nativeId'] for s in json.loads(self.read().stdout)['sessions']}, {'fork', 'plain'})
        self.assertNotEqual(self.read('detail', 'worker').returncode, 0)
        self.assertEqual(self.read('detail', 'fork').returncode, 0)

    def test_source_column_without_new_thread_source_column(self):
        self.schema('source-only')
        self.add('worker', {'subagent': {'thread_spawn': {}}}, None)
        self.add('plain', 'cli', None)
        self.assertEqual([s['nativeId'] for s in json.loads(self.read().stdout)['sessions']], ['plain'])

    def test_jd_cli144_schema_without_name(self):
        self.connection.execute('CREATE TABLE threads(id,title,cwd,git_branch,model,updated_at_ms,updated_at,archived,rollout_path,source,thread_source)')
        path = self.home / '.codex/sessions/jd.jsonl'
        path.write_text(json.dumps({'type':'response_item','payload':{'type':'message','role':'user','content':[{'type':'input_text','text':'JD history'}]}}))
        self.connection.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?,?)', ('jd','Existing JD','/fixture',None,'gpt-test',123000,123,0,str(path),'cli','user'))
        self.connection.commit()
        result = json.loads(self.read().stdout)
        self.assertEqual(result['warnings'], ['Hermes: unable to open database file'])
        self.assertEqual(result['sessions'][0]['title'], 'Existing JD')
        detail = self.read('detail', 'jd')
        self.assertEqual(detail.returncode, 0, detail.stderr)
        self.assertEqual(json.loads(detail.stdout)['events'][0]['text'], 'JD history')

    def test_minimal_schema_optional_columns_and_timestamp_fallback(self):
        self.connection.execute('CREATE TABLE threads(id,cwd,rollout_path,updated_at)')
        for id, timestamp in [('old', 10), ('new', 20)]:
            path = self.home / '.codex/sessions' / (id + '.jsonl')
            path.write_text(json.dumps({'type':'session_meta','payload':{'id':id,'source':'cli'}}))
            self.connection.execute('INSERT INTO threads VALUES(?,?,?,?)', (id,'/fixture',str(path),timestamp))
        self.connection.commit()
        result = json.loads(self.read().stdout)
        self.assertEqual([s['nativeId'] for s in result['sessions']], ['new','old'])
        self.assertEqual(result['sessions'][0]['updatedAt'], 20000)
        self.assertEqual(result['sessions'][0]['title'], '未命名会话')
        detail = self.read('detail','new')
        self.assertEqual(detail.returncode, 0, detail.stderr)
        self.assertEqual(json.loads(detail.stdout)['events'], [])

    def test_missing_required_schema_fails_closed(self):
        self.connection.execute('CREATE TABLE threads(id,title)')
        result = json.loads(self.read().stdout)
        self.assertEqual(result['sessions'], [])
        self.assertTrue(any('缺少必要字段' in warning for warning in result['warnings']))
        self.assertNotEqual(self.read('detail','missing').returncode,0)


if __name__ == '__main__':
    unittest.main()
