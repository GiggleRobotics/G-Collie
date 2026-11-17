import unittest
import tempfile
import pathlib
import base64
from process_records import ProcessRecords

class ProcessTests(unittest.TestCase):
    def test_parallel_calls_pair_by_id_not_result_order(self):
        events=[];p=ProcessRecords(events)
        p.start('a','terminal',{'command':'echo a'},1000,'a');p.start('b','terminal',{'command':'echo b'},1200,'b')
        p.finish('b','{"output":"b","exit_code":1}',1500);p.finish('a','a',2000)
        self.assertEqual(len(events),2);self.assertEqual(events[0]['text'],'a');self.assertEqual(events[1]['status'],'failed');self.assertEqual(events[0]['durationMs'],1000)
    def test_desktop_command_enriches_wrapper_without_duplicate_row(self):
        events=[];p=ProcessRecords(events)
        p.feed('response_item',{'type':'custom_tool_call','call_id':'c','name':'exec','input':'await run()'},1000,1)
        p.feed('event_msg',{'type':'item_completed','item':{'type':'CommandExecution','id':'native','command':['printf','OK'],'aggregated_output':'OK','exit_code':0}},1200,2)
        p.feed('response_item',{'type':'custom_tool_call_output','call_id':'c','output':'Script completed'},1500,3)
        self.assertEqual(len(events),1);self.assertEqual(events[0]['commands'][0]['command'],'printf OK');self.assertEqual(events[0]['status'],'completed')
    def test_async_shell_poll_merges_into_original_command(self):
        events=[];p=ProcessRecords(events)
        p.start('a','exec','await tools.exec_command({cmd:"sleep 1"})',1000,1)
        p.finish('a','{"session_id":123,"output":""}',1100)
        p.start('b','exec','await tools.write_stdin({session_id:123})',1200,2)
        p.finish('b','{"exit_code":0,"output":"OK"}',2000)
        self.assertEqual(len(events),1);self.assertEqual(events[0]['input'],'sleep 1');self.assertEqual(events[0]['status'],'completed')
    def test_only_public_reasoning_summary_is_exposed(self):
        events=[];p=ProcessRecords(events)
        p.feed('response_item',{'type':'reasoning','id':'r','summary':[],'content':'PRIVATE','encrypted_content':'PRIVATE'},1000,1)
        p.feed('event_msg',{'type':'item_completed','item':{'type':'Reasoning','id':'r','summary_text':[],'raw_content':'PRIVATE'}},1100,2)
        self.assertEqual(len(events),1);self.assertEqual(events[0]['text'],'');self.assertEqual(events[0]['status'],'completed')
        p.feed('event_msg',{'type':'item_completed','item':{'type':'Reasoning','id':'s','summary_text':['公开摘要'],'raw_content':'PRIVATE'}},1200,3)
        self.assertEqual(events[1]['text'],'公开摘要');self.assertNotIn('PRIVATE',str(events))
    def test_incomplete_call_is_not_invented_as_success(self):
        events=[];p=ProcessRecords(events);p.start('a','terminal',{'command':'sleep 10'},1000,1)
        self.assertEqual(events[0]['status'],'pending');self.assertNotIn('durationMs',events[0])

    def test_native_image_view_associates_call_and_deduplicates(self):
        events=[];p=ProcessRecords(events)
        p.feed('response_item',{'type':'function_call','name':'view_image','call_id':'c','arguments':'{"path":"/tmp/screen.png"}'},1000,1)
        item={'type':'item_completed','item':{'type':'ImageView','id':'i','path':'/tmp/screen.png'}}
        p.feed('event_msg',item,1200,2);p.feed('event_msg',item,1200,3)
        p.feed('response_item',{'type':'function_call_output','call_id':'c','output':'Image viewed'},1300,4)
        self.assertEqual(len(events),1);self.assertEqual(events[0]['media'],['/tmp/screen.png']);self.assertEqual(events[0]['status'],'completed')
    def test_native_image_view_without_call_retains_tool_record(self):
        events=[];p=ProcessRecords(events)
        p.feed('event_msg',{'type':'item_completed','item':{'type':'ImageView','id':'i','path':'/tmp/a.jpg'}},1000,1)
        self.assertEqual(len(events),1);self.assertEqual(events[0]['role'],'tool');self.assertEqual(events[0]['media'],['/tmp/a.jpg']);self.assertEqual(events[0]['status'],'completed')
        for path in ['https://evil.test/a.png','/tmp/secret.txt','/tmp/a.png\x00']:
            p.feed('event_msg',{'type':'item_completed','item':{'type':'ImageView','id':path,'path':path}},1000,2)
        self.assertEqual(len(events),1)
    def test_only_structured_tool_images_not_arbitrary_paths(self):
        events=[];p=ProcessRecords(events)
        p.start('c','tool','',1000,1)
        p.finish('c',{'content':[{'type':'text','text':'/tmp/private.png'},{'type':'local_image','path':'/tmp/a.png'},{'type':'image','mimeType':'image/png','data':'aGVsbG8='},{'type':'image_url','image_url':{'url':'https://evil.test/track.png'}}]},1100)
        self.assertEqual(events[0]['media'],['/tmp/a.png','data:image/png;base64,aGVsbG8='])
        self.assertEqual(events[0]['text'],'/tmp/private.png');self.assertNotIn('aGVsbG8=',events[0]['text'])
        p.start('d','tool','',1200,2);p.finish('d','![image](/tmp/private.png)',1300)
        self.assertNotIn('media',events[1])

    def test_native_view_overrides_same_call_inline_even_when_resized(self):
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'screen.png';path.write_bytes(b'image-one')
            inline='data:image/png;base64,'+base64.b64encode(b'image-one').decode()
            other='data:image/png;base64,'+base64.b64encode(b'image-two').decode()
            events=[];p=ProcessRecords(events)
            p.start('exec-call','exec','await tools.view_image(...)',1000,1)
            p.feed('event_msg',{'type':'item_completed','item':{'type':'ImageView','id':'native','path':str(path)}},1100,2)
            extra=pathlib.Path(folder)/'extra.png';extra.write_bytes(b'extra-local')
            p.finish('exec-call',[{'type':'image_url','image_url':inline},{'type':'image_url','image_url':other},{'type':'local_image','path':str(extra)}],1200)
            self.assertEqual(len(events),1);self.assertEqual(events[0]['media'],[str(path),str(extra)])
            p.start('next','exec','another invocation',1300,3)
            p.finish('next',[{'type':'image_url','image_url':inline}],1400)
            self.assertEqual(len(events),2);self.assertEqual(events[1]['media'],[inline])

    def test_native_inline_mirror_never_remains_in_tool_text(self):
        for text in ['', '工具说明']:
            with self.subTest(text=text):
                events=[];p=ProcessRecords(events)
                p.start('call','exec','view image',1000,1)
                p.feed('event_msg',{'type':'item_completed','item':{'type':'ImageView','id':'native','path':'/tmp/view.png'}},1100,2)
                blocks=[{'type':'image_url','image_url':'data:image/png;base64,aGVsbG8='}]
                if text:blocks.append({'type':'text','text':text})
                p.finish('call',{'content':blocks},1200)
                self.assertEqual(events[0]['media'],['/tmp/view.png'])
                self.assertEqual(events[0]['text'],text)
                self.assertNotIn('base64',events[0]['text']);self.assertNotIn('aGVsbG8=',events[0]['text']);self.assertNotIn('data:image',events[0]['text'])

unittest.main()
