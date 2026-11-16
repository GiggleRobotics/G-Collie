import{test}from'node:test';import assert from'node:assert/strict';import{applyDesktopPatches,desktopView}from'./desktop.js';
test('桌面增量支持消息追加、数组删除和状态替换',()=>{const s={items:[{text:'a'}],status:'running'};applyDesktopPatches(s,[{op:'replace',path:['items',0,'text'],value:'abc'},{op:'add',path:['items',1],value:{text:'b'}},{op:'remove',path:['items',0]},{op:'replace',path:['status'],value:'idle'}]);assert.deepEqual(s,{items:[{text:'b'}],status:'idle'})});
test('拒绝原型污染路径和缺失的增量路径',()=>{assert.throws(()=>applyDesktopPatches({},[{op:'add',path:['__proto__','polluted'],value:true}]));assert.throws(()=>applyDesktopPatches({},[{op:'replace',path:['unknown','text'],value:'x'}]));assert.equal(({} as any).polluted,undefined)});
test('只投影执行状态、轮次和用量，不导出整个内部快照',()=>{const view=desktopView({threadRuntimeStatus:{type:'active',activeFlags:['waitingOnApproval']},shellEnvironmentPolicy:{secret:'hidden'},turnHistory:{history:{entitiesByKey:{a:{turnId:'turn1',status:'inProgress'}}}},latestTokenUsageInfo:{total:{inputTokens:100,outputTokens:10,cachedInputTokens:80}}});assert.equal(view.status,'waiting');assert.equal(view.turnId,'turn1');assert.equal(view.readOnly,true);assert.equal(view.usage?.input,100);assert.equal((view as any).shellEnvironmentPolicy,undefined)});
import{desktopPending,desktopAnswer}from'./desktop.js';
test('桌面审批绑定原请求，过期审批不能误批新请求',()=>{const c={id:'t',requests:[{id:7,method:'item/commandExecution/requestApproval',params:{threadId:'t',turnId:'turn',command:'echo test',availableDecisions:['accept','decline']}}]};const p=desktopPending(c)!;assert.equal(p.kind,'approval');assert.deepEqual(desktopAnswer(c,{pendingId:p.id,decision:'accept'}),{method:'thread-follower-command-approval-decision',params:{conversationId:'t',requestId:7,decision:'accept'}});c.requests=[];assert.throws(()=>desktopAnswer(c,{pendingId:p.id,decision:'accept'}),/过期/)});
test('桌面问题要求每题有答案，响应不含内部上下文',()=>{const c={id:'t',requests:[{id:'q1',method:'item/tool/requestUserInput',params:{threadId:'t',turnId:'turn',questions:[{id:'color',question:'颜色？'}],secret:'never-export'}}]};const p=desktopPending(c)!;assert.equal((p.params as any).secret,undefined);assert.throws(()=>desktopAnswer(c,{pendingId:p.id,answers:{}}));assert.deepEqual(desktopAnswer(c,{pendingId:p.id,answers:{color:'blue'}}).params.response,{answers:{color:{answers:['blue']}}})});
test('文件审批使用文件响应通道，不能扩大桌面提供的授权选项',()=>{const c={id:'t',requests:[{id:'file',method:'item/fileChange/requestApproval',params:{threadId:'t',turnId:'turn',grantRoot:'/test',availableDecisions:['decline']}}]};const p=desktopPending(c)!;assert.throws(()=>desktopAnswer(c,{pendingId:p.id,decision:'accept'}),/未提供/);assert.equal(desktopAnswer(c,{pendingId:p.id,decision:'decline'}).method,'thread-follower-file-approval-decision')});
import {desktopSend} from './desktop.js';
test('执行中追加消息使用桌面 steer，不启动第二轮；附件也可单独发送',()=>{
 const b={text:'追加要求',requestId:'request-steer'};
 const active=desktopSend('thread',{status:'running',turnId:'turn'},b);
 assert.equal(active.method,'thread-follower-steer-turn');assert.equal(active.version,1);
 assert.equal(active.params.input![0].text,'追加要求');assert.equal(active.params.clientUserMessageId,b.requestId);assert.deepEqual(active.params.restoreMessage?.context,{});
 assert.equal(desktopSend('thread',{status:'idle'},b).method,'thread-follower-start-turn');
 assert.throws(()=>desktopSend('thread',{status:'unknown'},b),/尚未同步/);
 const image=desktopSend('thread',{status:'waiting',turnId:'turn'},{text:'',requestId:'image',attachments:[{image:true,path:'/selected/image.png'}]});
 assert.deepEqual(image.params.input,[{type:'localImage',path:'/selected/image.png'}]);
});

test('发送与执行中追加回执均提取原生轮次编号，历史回执兼容嵌套结构',async()=>{
 const {desktopReceiptTurnId}=await import('./desktop.js');
 assert.equal(desktopReceiptTurnId({result:{result:{turn:{id:'started'}}}}),'started');
 assert.equal(desktopReceiptTurnId({result:{result:{turnId:'steered'}}}),'steered');
 assert.equal(desktopReceiptTurnId({result:{turnId:'steered'}}),'steered');
 assert.equal(desktopReceiptTurnId({turnId:'stored'}),'stored');
 assert.equal(desktopReceiptTurnId({ok:true}),undefined);
});

test('等待审批时追加仍只走 steer，保留原审批请求且不产生审批决定',()=>{
 const c={id:'thread',threadRuntimeStatus:{type:'active',activeFlags:['waitingOnApproval']},turns:[{id:'turn',status:'inProgress'}],requests:[{id:7,method:'item/commandExecution/requestApproval',params:{threadId:'thread',turnId:'turn',availableDecisions:['accept','decline']}}]};
 const before=structuredClone(c),view=desktopView(c);
 assert.equal(view.status,'waiting');assert.ok(view.pending);
 const send=desktopSend('thread',view,{text:'补充范围',requestId:'waiting-steer'});
 assert.equal(send.method,'thread-follower-steer-turn');assert.equal('decision' in send.params,false);assert.deepEqual(c,before);
});

const asyncId=(item='async-message',index=0)=>JSON.stringify(['request_user_input_async',item,index]);
const asyncTurn=(status='inProgress',questions:any=[{title:'Choose a license',options:['GPLv3','Other']}])=>({turnId:'async-turn',status,items:[{type:'agentMessage',id:'async-message',questions,text:'question context'}]});
const asyncReply=(id=asyncId(),type='userMessage',status?:string):any=>({type,status,[type==='userMessage'?'content':'input']:[{type:'text',text:`<send_user_message_question_reply>\n${JSON.stringify({questionItemId:id,question:'Choose a license',answer:'GPLv3'})}\n</send_user_message_question_reply>`}]});

test('Codex宿主异步问题提供去电脑处理提示，不伪造可回答RPC',()=>{
 const c={id:'thread',requests:[],turns:[asyncTurn()]};
 const before=structuredClone(c),pending=desktopPending(c)!;
 assert.equal(pending.kind,'unsupported');assert.equal(pending.method,'request_user_input_async');
 assert.equal(pending.params.questions[0].question,'Choose a license');
 assert.equal(pending.params.questions[0].id,asyncId());
 assert.match(pending.params.reason,/电脑处理/);assert.equal(desktopView(c).status,'waiting');
 assert.throws(()=>desktopAnswer(c,{pendingId:pending.id,answers:{[asyncId()]:'GPLv3'}}),/桌面处理/);
 assert.deepEqual(c,before);
});

test('异步问题精确匹配已接受回答，支持跨轮及canonical历史',()=>{
 const question=asyncTurn();
 for(const reply of [asyncReply(),asyncReply(asyncId(),'steeringUserMessage','accepted')]){
  const c={id:'thread',turnHistory:{history:{entitiesByKey:{question,reply:{turnId:'reply-turn',status:'inProgress',items:[reply]}}}}};
  assert.equal(desktopPending(c),undefined);
 }
 const wrong={id:'thread',turns:[question,{items:[asyncReply(asyncId('different-message'))]}]};
 assert.ok(desktopPending(wrong));
 for(const status of ['pending','rejected',undefined])assert.ok(desktopPending({turns:[question,{items:[asyncReply(asyncId(),'steeringUserMessage',status)]}]}));
});

test('已结束异步问题、空问题和畸形数据不产生待处理',()=>{
 for(const status of ['completed','failed','interrupted'])assert.equal(desktopPending({turns:[asyncTurn(status)]}),undefined);
 for(const questions of [[],null,'question',[{}],[{title:'',options:[]}],[{title:'title',options:'invalid'}],[{title:'title',options:[1]}]]){
  assert.equal(desktopPending({turns:[asyncTurn('inProgress',questions)]}),undefined);
 }
 assert.equal(desktopPending({turns:[{turnId:'t',status:'inProgress',items:[{type:'agentMessage',text:'request_user_input_async: a plain message'}]}]}),undefined);
});

test('普通引用和无效回答不能隐藏真实未答问题',()=>{
 const text=asyncReply().content![0].text;
 for(const content of [[{type:'text',text:'quoted: '+text}],[{type:'text',text:'<send_user_message_question_reply>invalid</send_user_message_question_reply>'}],[{type:'text',text},{type:'text',text:'extra'}],[{type:'text',text:'<send_user_message_question_reply>{"questionItemId":"x"}</send_user_message_question_reply>'}]]){
  assert.ok(desktopPending({turns:[asyncTurn(),{items:[{type:'userMessage',content}]}]}));
 }
});

test('明确app-server审批优先于宿主异步问题',()=>{
 const c={id:'thread',turns:[asyncTurn()],requests:[{id:7,method:'item/commandExecution/requestApproval',params:{threadId:'thread',turnId:'async-turn'}}]};
 assert.equal(desktopPending(c)?.kind,'approval');
});

test('canonical已结束快照覆盖重复的旧执行中turn，多个问题只提示未答项',()=>{
 assert.equal(desktopPending({turns:[asyncTurn()],turnHistory:{history:{entitiesByKey:{a:asyncTurn('completed')}}}}),undefined);
 const turn=asyncTurn('inProgress',[{title:'First',options:['a']},{title:'Second',options:['b']}]);
 const pending=desktopPending({turns:[turn,{items:[asyncReply()]}]})!;
 assert.deepEqual(pending.params.questions,[{id:asyncId('async-message',1),question:'Second'}]);
});


test('明确终止systemError允许用户发起新轮，但不把未知或仍执行的错误当空闲',()=>{
 const b={text:'继续',requestId:'retry-error-turn'};
 const ended={threadRuntimeStatus:{type:'systemError'},turns:[{id:'ended',status:'failed'}]};
 const view=desktopView(ended);
 assert.equal(view.status,'idle');assert.equal(view.turnId,undefined);
 assert.equal(desktopSend('thread',view,b).method,'thread-follower-start-turn');
 for(const type of ['unknown','connecting',undefined]){
  const v=desktopView({...ended,threadRuntimeStatus:{type}});
  assert.equal(v.status,'unknown');assert.throws(()=>desktopSend('thread',v,b),/尚未同步/);
 }
 const active=desktopView({...ended,turns:[{id:'still-active',status:'inProgress'}]});
 assert.equal(active.status,'unknown');assert.throws(()=>desktopSend('thread',active,b),/尚未同步/);
 const pending=desktopView({...ended,id:'thread',requests:[{id:7,method:'item/commandExecution/requestApproval',params:{threadId:'thread',turnId:'ended'}}]});
 assert.equal(pending.status,'waiting');assert.throws(()=>desktopSend('thread',pending,b),/尚未同步/);
});
