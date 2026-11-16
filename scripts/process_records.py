"""Public process records only; never project raw/encrypted reasoning fields."""
import json
import re


def decoded(value):
    if isinstance(value, str):
        try: return json.loads(value)
        except (ValueError, TypeError): pass
    return value


def public_summary(value):
    if isinstance(value, str): return value[:12000]
    if isinstance(value, list):
        return '\n'.join(x if isinstance(x,str) else str(x.get('text','')) if isinstance(x,dict) else '' for x in value)[:12000]
    return ''


def command_text(command):
    if isinstance(command,list):
        if len(command)>=3 and re.search(r'(^|/)(?:ba|z)?sh$',str(command[0])) and command[1] in ['-lc','-c']:return str(command[2])
        return ' '.join(str(x) for x in command)
    return str(command or '')


def tool_input(value):
    obj=decoded(value)
    if isinstance(obj,dict):
        if isinstance(obj.get('duration_ms'),(int,float)):return '等待 '+str(obj['duration_ms']/1000).rstrip('0').rstrip('.')+' 秒'
        if 'cell_id' in obj:return '等待脚本执行结果'
        command=obj.get('command') or obj.get('cmd') or obj.get('code') or obj.get('query')
        if isinstance(command,list): command=command_text(command)
        return str(command or json.dumps(obj,ensure_ascii=False))[:16000]
    text=str(value or '')
    match=re.search(r'''["']?cmd["']?\s*:\s*("(?:\\.|[^"\\])*")''',text)
    if match:
        try:return str(json.loads(match[1]))[:16000]
        except ValueError:pass
    return text[:16000]


class ProcessRecords:
    def __init__(self,events):
        self.events=events
        self.calls={}
        self.open=[]
        self.turn=None
        self.turn_start=0
        self.thoughts=set()
        self.background={}

    def start(self,key,name,value,time,event_id):
        args=decoded(value)
        if name=='wait' and isinstance(args,dict) and str(args.get('cell_id')) in self.background:
            e=self.background[str(args['cell_id'])];self.calls[key]=e;self.open.append(key);return e
        sessions=set(re.findall(r'session_id[\"\']?\s*:\s*(\d+)',str(value)))
        if 'write_stdin' in str(value) and len(sessions)==1:
            prior=self.background.get('session:'+next(iter(sessions)))
            if prior is not None:self.calls[key]=prior;self.open.append(key);return prior
        e=dict(id=str(event_id),role='tool',text='',name=name or '工具',input=tool_input(value),status='pending',time=time,turnId=self.turn)
        self.events.append(e)
        self.calls[key]=e
        self.open.append(key)
        return e

    def finish(self,key,output,time,name='工具'):
        e=self.calls.get(key)
        if e is None:
            e=self.start(key,name,'',time,'result:'+str(key))
        e['text']=str(output or '')[:24000]
        e['status']='completed'
        obj=decoded(output)
        if isinstance(obj,dict):
            exit_code=obj.get('exit_code')
            if exit_code is None and isinstance(obj.get('result'),dict): exit_code=obj['result'].get('exit_code')
            if obj.get('isError') is True or exit_code is not None and exit_code!=0: e['status']='failed'
            if isinstance(obj.get('output'),str):
                e['text']=obj['output'][:22000]+('\n\n退出码：'+str(exit_code) if exit_code is not None else '')
                if obj.get('error'):e['text']+='\n'+str(obj['error'])[:1000];e['status']='failed'
        if e.get('commandFailed'): e['status']='failed'
        if re.search(r'Script running with cell ID|session_id["\s:]+\d+',str(output)):
            e['status']='submitted'
            match=re.search(r'Script running with cell ID\s+([^\s"\\]+)',str(output))
            if match:self.background[match[1]]=e
            session=re.search(r'session_id[\"\']?\s*:\s*(\d+)',str(output))
            if session:self.background['session:'+session[1]]=e
        if e.get('time') and time>=e['time']: e['durationMs']=time-e['time']
        if key in self.open: self.open.remove(key)
        return e

    def feed(self,kind,p,time,index):
        if kind=='response_item':
            t=p.get('type');key=p.get('call_id') or p.get('id') or str(index)
            if t in ['function_call','custom_tool_call']:
                self.start(key,p.get('name','工具'),p.get('arguments',p.get('input','')),time,index);return True
            if t in ['function_call_output','custom_tool_call_output']:
                self.finish(key,p.get('output',''),time);return True
            # Summaries are explicitly public. Do not inspect content/raw_content/encrypted_content.
            if t=='reasoning':
                self.summary(p.get('summary'),p.get('id') or key,time);return True
        if kind=='event_msg':
            t=p.get('type')
            if t=='task_started': self.turn=p.get('turn_id');self.turn_start=len(self.events)
            if t=='task_complete':
                if isinstance(p.get('duration_ms'),(int,float)):
                    position=next((i+1 for i in range(self.turn_start,len(self.events)) if self.events[i].get('role')=='user'),self.turn_start)
                    self.events.insert(position,dict(id='turn:'+str(p.get('turn_id',index)),role='process',text='本轮处理完成',durationMs=p['duration_ms'],time=time))
            if t=='item_started':
                item=p.get('item') or {}
                if item.get('type')=='Reasoning':
                    self.summary([],item.get('id') or str(index),time,'pending')
                    return True
            if t=='item_completed':
                item=p.get('item') or {};it=item.get('type')
                if it=='Reasoning': self.summary(item.get('summary_text'),item.get('id'),time)
                if it=='CommandExecution':
                    parent=next((self.calls[k] for k in reversed(self.open) if self.calls[k]['name'] in ['exec','wait','exec_command','write_stdin']),None)
                    if parent is None:
                        parent=self.start(item.get('id',index),'terminal',item.get('command'),p.get('started_at_ms') or time,'command:'+str(item.get('id',index)))
                        self.finish(item.get('id',index),item.get('aggregated_output',''),p.get('completed_at_ms') or time)
                    commands=parent.setdefault('commands',[])
                    command=item.get('command','')
                    if isinstance(command,list): command=command_text(command)
                    entry=dict(command=str(command)[:8000],output=str(item.get('aggregated_output') or '')[:12000],exitCode=item.get('exit_code'))
                    duration=item.get('duration')
                    if isinstance(duration,dict):entry['durationMs']=(duration.get('secs',0)*1000+duration.get('nanos',0)/1000000)
                    if not parent.get('durationMs') and entry.get('durationMs'):parent['durationMs']=entry['durationMs']
                    commands.append(entry)
                    if len(commands)>12:commands.pop(0)
                    if item.get('exit_code') not in [0,None]:parent['commandFailed']=True;parent['status']='failed'
                return True
        return False

    def summary(self,value,key,time,status='completed'):
        # A marker is public metadata, even when no public summary is supplied.
        text=public_summary(value).strip()
        existing=next((e for e in reversed(self.events) if e.get('role')=='reasoning' and e.get('sourceId')==str(key)),None)
        if existing is not None:
            if text:existing['text']=text
            existing['status']=status
            return
        if text and self.events and self.events[-1].get('role')=='reasoning' and self.events[-1].get('text')==text:return
        self.events.append(dict(id='summary:'+str(key),sourceId=str(key),role='reasoning',text=text,status=status,time=time,turnId=self.turn))
