import test from 'node:test';
import assert from 'node:assert/strict';
import {codexBackend} from './codex-control.js';
test('headless hosts use native control, desktop hosts retain their owner bridge',()=>{
 assert.equal(codexBackend({},false),'app-server');
 assert.equal(codexBackend({},true),'desktop');
 assert.equal(codexBackend({ORBIT_CODEX_BACKEND:'desktop'},false),'desktop');
 assert.equal(codexBackend({ORBIT_CODEX_BACKEND:'app-server'},true),'app-server');
 assert.throws(()=>codexBackend({ORBIT_CODEX_BACKEND:'fallback'},true));
});
