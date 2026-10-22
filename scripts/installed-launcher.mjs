import{mkdirSync,existsSync,writeFileSync,readFileSync,copyFileSync,readdirSync,chmodSync,unlinkSync}from'node:fs';
import{homedir}from'node:os';import{resolve,join}from'node:path';import{fileURLToPath}from'node:url';import{spawnSync,spawn}from'node:child_process';
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
else if(command==='doctor'){
 const headers={Authorization:'Bearer '+readFileSync(join(data,'access-token'),'utf8').trim()};
 try{const health=await fetch('http://127.0.0.1:4310/healthz',{signal:AbortSignal.timeout(5000)});if(!health.ok)throw Error('健康检查失败');const d=await(await fetch('http://127.0.0.1:4310/api/diagnostics',{headers,signal:AbortSignal.timeout(5000)})).json();const n=await(await fetch('http://127.0.0.1:4310/api/network/embedded',{headers,signal:AbortSignal.timeout(5000)})).json();console.log(JSON.stringify({service:'Running',version:d.version,codex:d.codex,network:{state:n.state,address:n.address},autostart:spawnSync('systemctl',['--user','is-enabled','--quiet',unit]).status===0},null,2));}catch(e){console.error('电脑服务未就绪：'+e.message);process.exitCode=1;}
}
else if(command==='uninstall-service'){systemctl('disable','--now',unit);const path=join(config,unit);if(existsSync(path))unlinkSync(path);systemctl('daemon-reload');console.log('后台服务已移除，登录和配对数据保留在 '+data);}

else throw Error('用法：g-collie [open|serve|install-service|start|stop|restart|status|uninstall-service|backup|doctor|migrate]');
