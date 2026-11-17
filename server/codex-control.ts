import {existsSync} from 'node:fs';
import {homedir} from 'node:os';
import {join} from 'node:path';

// Select once per service start. A failed desktop connection must never silently
// move an active conversation to an independently running CLI process.
export function codexBackend(env:NodeJS.ProcessEnv=process.env,hasDesktop=existsSync(join(homedir(),'.codex/ipc/ipc.sock'))):'desktop'|'app-server'{
 const selected=env.ORBIT_CODEX_BACKEND;
 if(selected!==undefined&&!['desktop','app-server','auto'].includes(selected))throw Error('ORBIT_CODEX_BACKEND 仅支持 auto、desktop 或 app-server');
 return selected==='desktop'||selected!=='app-server'&&hasDesktop?'desktop':'app-server';
}
