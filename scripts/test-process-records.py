import unittest
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

unittest.main()
