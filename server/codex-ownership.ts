import {readdirSync,readFileSync,statSync,existsSync} from 'node:fs';
import {basename,join} from 'node:path';
/** Independent app-server cannot observe another CLI's live execution. Fail closed
 * for any same-user Codex process, including desktops; do not kill or reconnect it.
 * Parent processes are intentionally NOT exempt: a Codex parent may own history.
 */
export function assertCodexResumeSafe(_id:string,_thread:any,bridgePid?:number,procRoot='/proc'){
 if(process.platform!=='linux'&&procRoot==='/proc')throw Error('此系统尚未验证终端会话独占状态，暂不接管');
 const descendant=(pid:number)=>{const seen=new Set<number>();while(pid>1&&!seen.has(pid)){if(pid===bridgePid)return true;seen.add(pid);try{const raw=readFileSync(join(procRoot,String(pid),'stat'),'utf8');pid=Number(raw.slice(raw.lastIndexOf(')')+2).split(' ')[1])}catch{return false}}return false};
 const uid=process.getuid?.();if(uid===undefined)throw Error('无法确认 Codex 进程属主');
 for(const name of readdirSync(procRoot)){if(!/^\d+$/.test(name)||Number(name)===process.pid||Number(name)===bridgePid)continue;const path=join(procRoot,name);let owner:number;try{owner=statSync(path).uid}catch(e){if(!existsSync(path))continue;throw Error('无法核实终端进程状态，暂不接管')}if(owner!==uid)continue;let args:string[];try{args=readFileSync(join(path,'cmdline'),'utf8').split('\0').filter(Boolean)}catch{if(!existsSync(path))continue;throw Error('无法读取终端进程状态，暂不接管')}if(!args.length||descendant(Number(name)))continue;
  const names=args.slice(0,3).map(a=>basename(a));
  if(names.some(n=>/^codex(?:[-_.](?:cli|app|linux|x64|aarch64|unknown).*)?$/.test(n)||n==='Codex')||args.some(a=>/\/@openai\/codex\/(?:bin|vendor)\//.test(a)))throw Error('其他 Codex 终端或桌面仍在运行；为避免接管冲突，请结束对应终端后再连接');
 }
}
