/** Real Codex process + loopback-only fake model. Never uses the user's CODEX_HOME or account. */
import { spawn, execFileSync, type ChildProcess } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import assert from 'node:assert/strict';
import { CodexAppServerBridge } from '../server/codex-app-server.js';

const binary = process.env.GCOLLIE_QA_CODEX || 'codex';
const daemonMode = process.env.GCOLLIE_QA_DAEMON === '1';
let daemon: ChildProcess | undefined;
let daemonSocket: string | false = false;
async function stopDaemon() {
  if (!daemon?.pid) return;
  const pid = daemon.pid;
  // This detached group belongs only to the temporary QA daemon we spawned.
  try { process.kill(-pid, 'SIGTERM'); } catch {}
  await new Promise(resolve => setTimeout(resolve, 250));
  try { process.kill(-pid, 'SIGKILL'); } catch {}
  if (daemon.exitCode === null && daemon.signalCode === null) await Promise.race([new Promise(resolve => daemon!.once('exit', resolve)), new Promise(resolve => setTimeout(resolve, 1000))]);
}
const home = await mkdtemp(join(tmpdir(), 'gcollie-codex-real-qa-'));
const audit: any[] = [], notifications: any[] = [], requests: any[] = [];
let mode = 'text';
let heldResponse: any;
let toolIssued = false;
let replyRequest: (item: any) => any = item => ({ decision: item.params?.availableDecisions?.includes('cancel') ? 'cancel' : 'decline' });
const http = createServer(async (req, res) => {
  let raw = ''; for await (const chunk of req) raw += chunk;
  const body = raw ? JSON.parse(raw) : {};
  audit.push({ path: req.url, mode, body });
  if (mode === 'hold') { heldResponse = res; res.writeHead(200, { 'content-type': 'text/event-stream' }); res.write(': waiting\n\n'); return; }
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  const id = `resp_qa_${audit.length}`;
  let msg: any = { id: `msg_qa_${audit.length}`, type: 'message', status: 'completed', role: 'assistant', content: [{ type: 'output_text', text: 'GCOLLIE_REAL_APP_SERVER_OK', annotations: [] }] };
  if ((mode === 'approval' || mode === 'question') && !toolIssued) {
    toolIssued = true;
    msg = { type: 'function_call', id: `fc_qa_${audit.length}`, call_id: `call_qa_${audit.length}`, name: mode === 'approval' ? 'exec_command' : 'request_user_input', arguments: JSON.stringify(mode === 'approval' ? { cmd: 'printf NEVER_RUN_QA', sandbox_permissions: 'require_escalated', justification: 'QA rejection only; must never run' } : { questions: [{ id: 'qa_color', header: 'QA', question: 'Choose a QA color', options: [{label:'Blue',description:'QA blue'},{label:'Green',description:'QA green'}] }] }) };
  }
  const event = (type: string, extra: any) => res.write(`event: ${type}\ndata: ${JSON.stringify({ type, ...extra })}\n\n`);
  event('response.created', { response: { id, object: 'response', status: 'in_progress', output: [] } });
  event('response.output_item.added', { output_index: 0, item: { ...msg, status: 'in_progress', content: [] } });
  if (msg.type === 'message') event('response.content_part.added', { item_id: msg.id, output_index: 0, content_index: 0, part: { type: 'output_text', text: '', annotations: [] } });
  if (msg.type === 'message') event('response.output_text.delta', { item_id: msg.id, output_index: 0, content_index: 0, delta: 'GCOLLIE_REAL_APP_SERVER_OK' });
  event('response.output_item.done', { output_index: 0, item: msg });
  event('response.completed', { response: { id, object: 'response', status: 'completed', output: [msg], usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 } } });
  res.end();
});
await new Promise<void>(resolve => http.listen(0, '127.0.0.1', resolve));
const port = (http.address() as any).port;
await writeFile(join(home, 'config.toml'), `model = "gpt-5.4"\nmodel_provider = "qa"\n[model_providers.qa]\nname = "Loopback QA"\nbase_url = "http://127.0.0.1:${port}/v1"\nwire_api = "responses"\nenv_key = "GCOLLIE_QA_DUMMY_KEY"\n`);
const child = spawn(binary, ['app-server', '--listen', 'stdio://'], { env: { ...process.env, CODEX_HOME: home, GCOLLIE_QA_DUMMY_KEY: 'not-a-real-key', OPENAI_API_KEY: 'not-a-real-key' }, stdio: ['pipe', 'pipe', 'pipe'] });
let stderr = '';
child.stderr.on('data', c => { stderr += c; });
let seq = 0;
const pending = new Map<number, { resolve: (v: any) => void, reject: (e: Error) => void }>();
const rl = createInterface({ input: child.stdout });
rl.on('line', line => {
  let item: any; try { item = JSON.parse(line); } catch { return; }
  if (item.id !== undefined && !item.method) {
    const p = pending.get(item.id); if (!p) return; pending.delete(item.id);
    item.error ? p.reject(new Error(JSON.stringify(item.error))) : p.resolve(item.result);
  } else if (item.id !== undefined) { requests.push(item); child.stdin.write(JSON.stringify({ id: item.id, result: replyRequest(item) }) + '\n'); }
  else notifications.push(item);
});
function call(method: string, params: any) { return new Promise<any>((resolve, reject) => { const id = ++seq; const timer = setTimeout(() => { pending.delete(id); reject(new Error(`timeout ${method}: ${stderr.slice(-1500)}`)); }, 30000); pending.set(id, { resolve: v => { clearTimeout(timer); resolve(v); }, reject: e => { clearTimeout(timer); reject(e); } }); child.stdin.write(JSON.stringify({ id, method, params }) + '\n'); }); }
async function until(fn: () => any, label: string) { const end = Date.now() + 30000; while (Date.now() < end) { const v = await fn(); if (v) return v; await new Promise(r => setTimeout(r, 30)); } throw new Error(`timeout ${label}: ${stderr.slice(-2000)}`); }
const input = (text: string) => [{ type: 'text', text, text_elements: [] }];
const checks: string[] = [];
try {
  const init = await call('initialize', { clientInfo: { name: 'gcollie_real_qa', version: '1.0' }, capabilities: { experimentalApi: true } });
  child.stdin.write(JSON.stringify({ method: 'initialized', params: {} }) + '\n');
  const start = await call('thread/start', { cwd: home, approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true });
  const threadId = start.thread.id; assert.ok(threadId); checks.push('real thread/start');
  const sent = await call('turn/start', { threadId, input: input('QA_TEXT') });
  await until(() => notifications.find(n => n.method === 'turn/completed' && n.params.turn.id === sent.turn.id), 'text completed');
  assert.ok(notifications.some(n => JSON.stringify(n).includes('GCOLLIE_REAL_APP_SERVER_OK'))); checks.push('real turn/start and streamed assistant output');
  const image = join(home, 'qa.png');
  await writeFile(image, Buffer.from('iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKUlEQVR4nO3NMQEAAAjDsIF/z2ACvlRAU8nks369AwAAAAAAAAAAgMMWocYBP7wfsd0AAAAASUVORK5CYII=', 'base64'));
  const imageTurn = await call('turn/start', { threadId, input: [...input('QA_IMAGE'), { type: 'localImage', path: image }] });
  await until(() => notifications.find(n => n.method === 'turn/completed' && n.params.turn.id === imageTurn.turn.id), 'image completed');
  assert.ok(audit.some(a => JSON.stringify(a.body).includes('input_image')), 'native localImage must reach localhost model as input_image'); checks.push('real localImage converted to model input_image');
  mode = 'hold'; heldResponse = undefined;
  const active = await call('turn/start', { threadId, input: input('QA_WAIT') });
  await until(() => heldResponse, 'held model request');
  await call('turn/steer', { threadId, expectedTurnId: active.turn.id, input: input('QA_APPEND') }); checks.push('real turn/steer active turn');
  await assert.rejects(call('turn/steer', { threadId, expectedTurnId: 'stale-turn', input: input('QA_STALE') })); checks.push('stale turn steer denied');
  await call('turn/interrupt', { threadId, turnId: active.turn.id });
  const stopped = await until(() => notifications.find(n => n.method === 'turn/completed' && n.params.turn.id === active.turn.id), 'interrupt completed');
  assert.equal(stopped.params.turn.status, 'interrupted'); checks.push('real turn/interrupt');
  for (const kind of ['approval', 'question']) {
    mode = kind; toolIssued = false;
    const previous = requests.length;
    const t = await call('thread/start', { cwd: home, approvalPolicy: 'on-request', sandbox: 'read-only', ephemeral: true, config: { 'features.default_mode_request_user_input': true } });
    replyRequest = item => item.method === 'item/tool/requestUserInput' ? { answers: { qa_color: { answers: ['Green'] } } } : { decision: item.params?.availableDecisions?.includes('cancel') ? 'cancel' : 'decline' };
    const turn = await call('turn/start', { threadId: t.thread.id, input: input(`QA_${kind}`) });
    await until(() => notifications.find(n => n.method === 'turn/completed' && n.params.turn.id === turn.turn.id), `${kind} completed`);
    assert.ok(requests.length > previous, `${kind} produced no app-server request`);
    checks.push(`real ${requests.at(-1).method} response roundtrip`);
  }
  const savedHome = process.env.CODEX_HOME, savedKey = process.env.GCOLLIE_QA_DUMMY_KEY;
  process.env.CODEX_HOME = home; process.env.GCOLLIE_QA_DUMMY_KEY = 'not-a-real-key';
  if (daemonMode) {
    daemonSocket = join(home, 'qa.sock');
    daemon = spawn(binary, ['app-server', '--listen', `unix://${daemonSocket}`], { detached: true, env: { ...process.env, CODEX_HOME: home, GCOLLIE_QA_DUMMY_KEY: 'not-a-real-key', OPENAI_API_KEY: 'not-a-real-key' }, stdio: ['ignore', 'pipe', 'pipe'] });
    daemon.stderr?.on('data', c => { stderr = (stderr + c).slice(-4000); });
    daemon.on('error', e => { stderr += `QA daemon spawn failed: ${e.message}`; });
    await until(() => { if (daemon!.exitCode !== null || daemon!.signalCode !== null) throw new Error(`QA Codex CLI does not support this Unix daemon launch: ${stderr.slice(-2000)}`); return stat(daemonSocket as string).then(st => st.isSocket()).catch(() => false); }, 'temporary Unix daemon socket');
    const socket = await stat(daemonSocket); assert.ok(socket.isSocket());
  }
  const bridge = new CodexAppServerBridge(join(home, 'bridge'), () => {}, { bin: binary, daemonSocket,  assertResumeSafe: async () => {} });
  try {
    mode = 'text';
    if (daemonMode) { const status = await bridge.status(); assert.equal(status.available, true); assert.equal(status.backend, 'daemon'); checks.push('bridge backend=daemon via real temporary Unix WebSocket'); }
    const bridgeStartAudit = audit.length;
    const created = await bridge.create({ requestId: 'qa_bridge_create', prompt: 'QA_BRIDGE_TEXT', cwd: home, mediaPrepared: true, attachments: [{ path: image, image: true, name: 'qa.png', mime: 'image/png' }] });
    await until(() => audit.length > bridgeStartAudit && bridge.view(created.threadId).status === 'idle', 'bridge create complete');
    assert.ok(created.id.startsWith('codex:')); assert.ok(JSON.stringify(audit.at(-1)?.body).includes('input_image')); checks.push('bridge create+image via real app-server');
    mode = 'hold'; heldResponse = undefined;
    await bridge.action(created.threadId, { action: 'send', requestId: 'qa_bridge_wait', text: 'QA_BRIDGE_WAIT' });
    await until(() => heldResponse && bridge.view(created.threadId).turnId, 'bridge active');
    const activeId = bridge.view(created.threadId).turnId;
    await bridge.action(created.threadId, { action: 'send', requestId: 'qa_bridge_append', text: 'QA_BRIDGE_APPEND' });
    await bridge.action(created.threadId, { action: 'stop', requestId: 'qa_bridge_stop', turnId: activeId });
    await until(() => bridge.view(created.threadId).status === 'idle', 'bridge stop');
    checks.push('bridge send/steer/stop via real app-server');
    for (const kind of ['approval', 'question']) {
      mode = kind; toolIssued = false;
      await bridge.action(created.threadId, { action: 'send', requestId: `qa_bridge_${kind}`, text: `QA_BRIDGE_${kind}` });
      const pending = await until(() => bridge.view(created.threadId).pending, `bridge ${kind}`);
      assert.equal(pending.kind, kind);
      await bridge.action(created.threadId, { action: 'answer', requestId: `qa_bridge_answer_${kind}`, pendingId: pending.id, decision: 'decline', answers: { qa_color: 'Green' } });
      await until(() => bridge.view(created.threadId).status === 'idle', `bridge ${kind} response`);
      checks.push(`bridge ${kind} response via real app-server`);
    }
  } finally { bridge.close(); if (savedHome === undefined) delete process.env.CODEX_HOME; else process.env.CODEX_HOME = savedHome; if (savedKey === undefined) delete process.env.GCOLLIE_QA_DUMMY_KEY; else process.env.GCOLLIE_QA_DUMMY_KEY = savedKey; }
  console.log(JSON.stringify({ binary, version: execFileSync(binary, ['--version'], { encoding: 'utf8' }).trim(), transport: daemonMode ? 'raw real app-server stdio; bridge real temporary Unix WebSocket daemon' : 'real app-server stdio', model: 'loopback Responses fixture; dummy credentials; ephemeral CODEX_HOME', checks, requestCount: audit.length, serverRequests: requests.map(r => r.method), notifications: [...new Set(notifications.map(n => n.method))], initialize: init, untested: ['production account/model access', 'real user threads', 'plan mode'] }, null, 2));
} finally { await stopDaemon(); heldResponse?.destroy(); child.kill('SIGTERM'); http.closeAllConnections(); http.close(); rl.close(); await new Promise(resolve => setTimeout(resolve, 250)); await rm(home, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 }); }
