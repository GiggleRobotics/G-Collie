export type HistoryOptions={before?:string};
export function historyPage(events:any[],before?:string,limit=200){
 let end=events.length;
 if(before){if(before.length>2048)throw Error('无效历史游标');let key:any;try{key=JSON.parse(Buffer.from(before,'base64url').toString())}catch{throw Error('无效历史游标')}
 end=events.findIndex(e=>Array.isArray(key)&&key[0]===String(e.id)&&key[1]===(e.time||0));if(end<0)throw Error('历史位置已变化，请刷新会话');}
 const start=Math.max(0,end-limit),page=events.slice(start,end);
 return{events:page,historyLimit:limit,hasMoreHistory:start>0,historyCursor:start>0&&page.length?Buffer.from(JSON.stringify([String(page[0].id),page[0].time||0])).toString('base64url'):null};
}
