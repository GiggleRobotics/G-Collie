import {test} from 'node:test';import assert from 'node:assert/strict';import {applyAction,seeds} from './core.js';
test('审批只处理一次，过期审批不能作用于下一轮',()=>{const t=seeds()[1];applyAction(t,'approve',undefined,'approval-demo');assert.equal(t.status,'running');assert.throws(()=>applyAction(t,'approve',undefined,'approval-demo'));});
test('真实适配器未接入时拒绝控制',()=>{const t=seeds()[0];t.demo=false;assert.throws(()=>applyAction(t,'stop'));});
test('停止清除审批，空消息不改变状态',()=>{const t=seeds()[1];applyAction(t,'stop');assert.equal(t.approval,undefined);assert.throws(()=>applyAction(t,'message',' '));assert.equal(t.status,'stopped')});
