"""Stable backwards pages over projected events, independent of new tail messages."""
import base64
import json


def history_page(events, before=None, limit=200):
    end=len(events)
    if before:
        if not isinstance(before,str) or len(before)>2048:raise ValueError('无效历史游标')
        try:
            key=json.loads(base64.urlsafe_b64decode(before+'='*(-len(before)%4)))
            end=next(i for i,e in enumerate(events) if [str(e['id']),e.get('time',0)]==key)
        except (ValueError,TypeError,KeyError,StopIteration):raise ValueError('历史位置已变化，请刷新会话')
    start=max(0,end-limit)
    page=events[start:end]
    cursor=base64.urlsafe_b64encode(json.dumps([str(page[0]['id']),page[0].get('time',0)],ensure_ascii=False,separators=(',',':')).encode()).decode().rstrip('=') if start>0 and page else None
    return dict(events=page,historyLimit=limit,hasMoreHistory=start>0,historyCursor=cursor)
