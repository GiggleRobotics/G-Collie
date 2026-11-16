"""Isolated project/media/usage fixtures; run with Python 3.8 or newer."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
ROOT = Path(os.environ.get('GCOLLIE_TEST_SCRIPTS', str(Path(__file__).resolve().parent)))
sys.path.insert(0, str(ROOT))
from path_compat import is_relative_to
from message_display import codex_generated_image

class CompatibilityTests(unittest.TestCase):
    def test_path_boundaries(self):
        self.assertTrue(is_relative_to(Path('/a/b'), Path('/a')))
        self.assertTrue(is_relative_to(Path('/a'), Path('/a')))
        self.assertFalse(is_relative_to(Path('/ab'), Path('/a')))
        self.assertFalse(is_relative_to(Path('/b/a'), Path('/a')))
        self.assertFalse(is_relative_to(Path('a'), Path('/a')))

    def test_project_rollout_media_and_usage(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder); codex = home/'.codex'; session = codex/'sessions/test.jsonl'
            session.parent.mkdir(parents=True)
            project = home/'project'; project.mkdir(); child = project/'sub'; child.mkdir()
            outside = home/'outside'; outside.mkdir()
            (project/'escape').symlink_to(outside, target_is_directory=True)
            self.assertFalse(is_relative_to((project/'escape').resolve(), project.resolve()))
            (codex/'.codex-global-state.json').write_text(json.dumps({'local-projects': {'p': {'rootPaths': [str(project)], 'name': 'Fixture Project'}}}))
            generated = codex/'generated_images/test/image.png';generated.parent.mkdir(parents=True);generated.write_bytes(b'fixture')
            payload={'type':'item_completed','item':{'type':'Extension','kind':'image_gen.generation','status':'completed','savedPath':str(generated)}}
            self.assertEqual(codex_generated_image('event_msg',payload,home,'test'),str(generated))
            self.assertIsNone(codex_generated_image('event_msg',payload,home,'other'))
            rows=[{'type':'response_item','timestamp':'2026-11-15T00:00:00Z','payload':{'type':'message','id':'u','role':'user','content':[{'type':'input_text','text':'fixture input'}]}}, {'type':'event_msg','timestamp':'2026-11-15T00:00:01Z','payload':payload}, {'type':'event_msg','timestamp':'2026-11-15T00:00:02Z','payload':{'type':'token_count','info':{'total_token_usage':{'input_tokens':10,'output_tokens':3,'cached_input_tokens':2}}}}]
            session.write_text('\n'.join(json.dumps(r) for r in rows))
            with sqlite3.connect(codex/'state_5.sqlite') as conn:
                conn.execute('CREATE TABLE threads(id,title,name,cwd,git_branch,model,updated_at_ms,updated_at,archived,rollout_path,tokens_used,created_at)')
                conn.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',('test','Fixture',None,str(child),None,'fixture',1,1,0,str(session),13,1))
            env=dict(os.environ,HOME=str(home),GCOLLIE_USAGE_HOME=str(home),GCOLLIE_DATA_DIR=str(home/'data'))
            def run(script,*args):return json.loads(subprocess.check_output([sys.executable,str(ROOT/script)]+list(args),env=env,universal_newlines=True))
            index=run('read-local.py','list');self.assertEqual(index['sessions'][0]['project'],'Fixture Project');self.assertFalse(any(w.startswith('Codex:') for w in index['warnings']))
            detail=run('read-local.py','detail','codex:test');self.assertTrue(any(str(generated) in e.get('media',[]) for e in detail['events']))
            usage=run('read-usage.py');self.assertFalse(any(w.startswith('Codex ') for w in usage['warnings']));self.assertEqual(usage['agents']['Codex']['sessions'][0]['project'],'Fixture Project');self.assertEqual(usage['agents']['Codex']['total']['input'],10)
            # Real-path containment remains enforced after replacing the 3.9 method.
            session.unlink();session.symlink_to(outside/'not-a-rollout')
            bad=subprocess.run([sys.executable,str(ROOT/'read-local.py'),'detail','codex:test'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            self.assertNotEqual(bad.returncode,0);self.assertIn('会话文件超出允许范围',bad.stderr.decode())

if __name__ == '__main__':unittest.main()
