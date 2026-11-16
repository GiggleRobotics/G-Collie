import{mkdirSync,existsSync,writeFileSync,readFileSync,copyFileSync,readdirSync,chmodSync,unlinkSync}from'node:fs';
import{homedir,networkInterfaces}from'node:os';import{resolve,join}from'node:path';import{fileURLToPath}from'node:url';import{spawnSync,spawn}from'node:child_process';import http from'node:http';
const root=resolve(fileURLToPath(new URL('.',import.meta.url))),data=process.env.GCOLLIE_DATA_DIR||join(process.env.XDG_DATA_HOME||join(homedir(),'.local/share'),'g-collie');
mkdirSync(data,{recursive:true,mode:0o700});
const command=process.argv[2]||'open',unit='g-collie.service',config=join(process.env.XDG_CONFIG_HOME||join(homedir(),'.config'),'systemd/user');
const quote=v=>'"'+v.replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/%/g,'%%')+'"';
const systemctl=(...args)=>{const r=spawnSync('systemctl',['--user',...args],{stdio:'inherit'});if(r.status!==0)throw Error('后台服务操作失败，请确认当前用户已登录桌面。');};
function configure(){mkdirSync(config,{recursive:true});
 const networkEnv=Object.fromEntries(['HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','http_proxy','https_proxy','all_proxy','no_proxy'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]));if(Object.keys(networkEnv).length)writeFileSync(join(data,'codex-network-env.json'),JSON.stringify(networkEnv),{mode:0o600});
 if(process.env.CODEX_APP_TOOLS_PIPE_PATH&&process.env.CODEX_THREAD_ID)writeFileSync(join(data,'desktop-runtime.json'),JSON.stringify({pipe:process.env.CODEX_APP_TOOLS_PIPE_PATH,context:process.env.CODEX_THREAD_ID}),{mode:0o600});
 writeFileSync(join(config,unit),`[Unit]\nDescription=G-Collie Agent console\nAfter=network.target\n[Service]\nType=simple\nWorkingDirectory=${root.replace(/%/g,'%%')}\nExecStart=${quote(join(root,'runtime/node'))} ${quote(join(root,'server.mjs'))}\nEnvironment=NODE_ENV=production\nEnvironment=HOST=127.0.0.1\nEnvironment=${quote('GCOLLIE_DATA_DIR='+data)}\nRestart=on-failure\nRestartSec=3\nUMask=0077\nNoNewPrivileges=true\n[Install]\nWantedBy=default.target\n`,{mode:0o600});systemctl('daemon-reload');systemctl('enable',unit);}
if(command==='serve'){process.chdir(root);process.env.GCOLLIE_DATA_DIR=data;process.env.NODE_ENV='production';await import('./server.mjs');}
else if(command==='migrate'){const from=resolve(process.argv[3]||'');if(!process.argv[3]||!existsSync(join(from,'access-token')))throw Error('用法：g-collie migrate /原项目/.data');if(readdirSync(data).length)throw Error('目标数据目录不为空，禁止覆盖现有配对数据');for(const f of readdirSync(from))if(/\.(json|jsonl)$/.test(f)||f==='access-token')copyFileSync(join(from,f),join(data,f));console.log('已迁移本机数据；安装包不会包含这些文件。');}
else if(command==='open'||command==='install-service'){configure();systemctl('restart',unit);for(let i=0;i<100;i++){try{if((await fetch('http://127.0.0.1:4310/healthz')).ok)break;}catch{}await new Promise(r=>setTimeout(r,100));}
 if(command==='open'){const key=readFileSync(join(data,'access-token'),'utf8').trim();const child=spawn('xdg-open',['http://127.0.0.1:4310/#token='+encodeURIComponent(key)],{stdio:'ignore',detached:true});child.unref();}}
else if(['start','stop','restart','status'].includes(command))systemctl(command,unit,...(command==='status'?['--no-pager']:[]));
else if(command==='backup'){
 const wasRunning=spawnSync('systemctl',['--user','is-active','--quiet',unit]).status===0;
 const folder=join(homedir(),'.local/share/g-collie-backups');mkdirSync(folder,{recursive:true,mode:0o700});chmodSync(folder,0o700);
 const stamp=new Date().toISOString().replace(/[:.]/g,'-');const archive=join(folder,'g-collie-'+stamp+'.tar.gz');
 if(wasRunning)systemctl('stop',unit);
 try{const result=spawnSync('tar',['-czf',archive,'-C',data,'.'],{stdio:'inherit'});if(result.status!==0){if(existsSync(archive))unlinkSync(archive);throw Error('备份失败，未保留不完整文件')}chmodSync(archive,0o600);console.log('本机私有备份：'+archive);console.log('备份包含设备凭证和网络身份，请勿公开分享。');}finally{if(wasRunning)systemctl('start',unit);}
}
else if(command==='pair'){
 try{
  const args=process.argv.slice(3),json=args.includes('--json'),addresses=args.filter(a=>a!=='--json');
  if(addresses.length>1||addresses.some(a=>a.startsWith('-')))throw Error('用法：g-collie pair [本机服务地址] [--json]');
  const local=new Set(['127.0.0.1','localhost',...Object.values(networkInterfaces()).flat().filter(Boolean).filter(n=>n.family==='IPv4').map(n=>n.address)]);
  const port=Number(process.env.PORT||4310);
  const candidates=addresses.length?addresses:[`http://127.0.0.1:${port}`,...[...local].filter(h=>/^100\./.test(h)).map(h=>`http://${h}:${port}`)];
  const urls=candidates.map(value=>{const u=new URL(value);if(u.protocol!=='http:'||!local.has(u.hostname)||u.username||u.password||u.search||u.hash||u.pathname!=='/')throw Error('服务地址必须是本机网卡或回环的HTTP地址，不接受远端地址、路径或凭证');return u;});
  const key=readFileSync(join(data,'access-token'),'utf8').trim();
  const call=(u,path,body)=>new Promise((resolve,reject)=>{const bytes=body===undefined?undefined:JSON.stringify(body);const req=http.request({hostname:u.hostname==='localhost'?'127.0.0.1':u.hostname,port:u.port||80,localAddress:'127.0.0.1',path:'/api'+path,method:bytes?'POST':'GET',headers:{Host:`127.0.0.1:${u.port||80}`,Authorization:'Bearer '+key,...(bytes?{'Content-Type':'application/json','Content-Length':Buffer.byteLength(bytes)}:{})}},res=>{let content='';res.on('data',chunk=>{content+=chunk;if(content.length>2*1024*1024)req.destroy(Error('服务响应过大'));});res.on('end',()=>{try{const value=JSON.parse(content);if(res.statusCode!==200)throw Error(value.error||`HTTP ${res.statusCode}`);resolve(value);}catch(e){reject(e);}});});req.setTimeout(5000,()=>req.destroy(Error('连接超时')));req.on('error',reject);req.end(bytes);});
  let selected,network;
  for(const u of urls){try{network=await call(u,'/network');selected=u;break;}catch{}}
  if(!selected)throw Error('无法管理本机服务，请确认服务运行、数据目录属于同一用户；非默认端口请显式传入本机服务地址');
  const invite=await call(selected,'/devices/pair',{});
  const origin=network.embedded?.address||network.tailscale?.httpsURL||network.pairingAddresses?.[0]||selected.origin;
  const link=new URL(invite.url);link.protocol=new URL(origin).protocol;link.host=new URL(origin).host;
  const result={code:invite.code,url:link.toString(),expiresAt:invite.expiresAt,address:origin};
  if(json)console.log(JSON.stringify(result));else{console.log('访问地址：'+origin);console.log('六位配对码：'+invite.code);console.log('配对链接：'+result.url);console.log('有效期至：'+new Date(invite.expiresAt).toISOString()+'（10分钟内、一次使用；新码替换旧码）');console.log('手机或远程浏览器填地址和六位码。此码授予会话控制权限，请勿公开。');if(['127.0.0.1','localhost'].includes(new URL(origin).hostname))console.log('当前只有本机地址；请先通过SSH转发进入电脑管理端配置内置远程连接，手机不能直接使用此地址。');}
 }catch(e){console.error('生成配对码失败：'+e.message);process.exitCode=1;}
}
else if(command==='doctor'){
 const headers={Authorization:'Bearer '+readFileSync(join(data,'access-token'),'utf8').trim()};
 try{const health=await fetch('http://127.0.0.1:4310/healthz',{signal:AbortSignal.timeout(5000)});if(!health.ok)throw Error('健康检查失败');const d=await(await fetch('http://127.0.0.1:4310/api/diagnostics/system',{headers,signal:AbortSignal.timeout(5000)})).json();const n=await(await fetch('http://127.0.0.1:4310/api/network/embedded',{headers,signal:AbortSignal.timeout(5000)})).json();console.log(JSON.stringify({service:'Running',version:d.version,codex:d.codex,network:{state:n.state,address:n.address},autostart:spawnSync('systemctl',['--user','is-enabled','--quiet',unit]).status===0},null,2));}catch(e){console.error('电脑服务未就绪：'+e.message);process.exitCode=1;}
}
else if(command==='uninstall-service'){systemctl('disable','--now',unit);const path=join(config,unit);if(existsSync(path))unlinkSync(path);systemctl('daemon-reload');console.log('后台服务已移除，登录和配对数据保留在 '+data);}

else throw Error('用法：g-collie [open|serve|install-service|start|stop|restart|status|uninstall-service|backup|doctor|pair|migrate]');
