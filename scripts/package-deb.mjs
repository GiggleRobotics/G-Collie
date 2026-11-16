import{mkdir,rm,cp,writeFile,readFile,chmod,rename}from'node:fs/promises';import{resolve,join}from'node:path';import{execFileSync}from'node:child_process';import{build}from'esbuild';
const root=resolve('.'),stage=join(root,'.packaging/deb'),app=join(stage,'usr/lib/g-collie'),version=JSON.parse(await readFile('package.json','utf8')).version;
await rm(stage,{recursive:true,force:true});await mkdir(app,{recursive:true});await cp('.packaging/network/g-collie-network',join(app,'g-collie-network'));await chmod(join(app,'g-collie-network'),0o755);
execFileSync('npm',['run','build'],{stdio:'inherit'});
const bundled=await build({metafile:true,entryPoints:['server/index.ts'],bundle:true,platform:'node',format:'esm',target:'node22',outfile:join(app,'server.mjs'),external:['vite'],banner:{js:"import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);"}});
for(const [src,dest]of [['dist','dist'],['scripts/path_compat.py','scripts/path_compat.py'],['scripts/read-local.py','scripts/read-local.py'],['scripts/message_display.py','scripts/message_display.py'],['scripts/process_records.py','scripts/process_records.py'],['scripts/history_page.py','scripts/history_page.py'],['scripts/read-usage.py','scripts/read-usage.py'],['scripts/installed-launcher.mjs','launcher.mjs']]){await mkdir(join(app,dest,'..'),{recursive:true});await cp(src,join(app,dest),{recursive:true});}
await mkdir(join(app,'preview-assets'),{recursive:true});for(const name of ['pdf.mjs','pdf.worker.mjs'])await cp(join('node_modules/pdfjs-dist/legacy/build',name),join(app,'preview-assets',name));
const ffmpegRoot=resolve('.tools/ffmpeg-release');
await cp(join(ffmpegRoot,'ffmpeg'),join(app,'ffmpeg'));await chmod(join(app,'ffmpeg'),0o755);
await mkdir(join(stage,'usr/share/doc/g-collie/ffmpeg'),{recursive:true});
for(const name of ['ffmpeg-7.0.2.tar.xz','COPYING.LGPLv2.1','build.sh','build-info.txt','source.json'])await cp(join(ffmpegRoot,name),join(stage,'usr/share/doc/g-collie/ffmpeg',name));
await writeFile(join(stage,'usr/share/doc/g-collie/ffmpeg/README'),'FFmpeg 7.0.2 built from unmodified official source without external optional codecs, licensed LGPL-2.1-or-later. Complete corresponding source, configure/build script and provenance accompany this binary in this directory. zlib is a system library. The old third-party GPL static binary is not shipped.\n');
await mkdir(join(app,'runtime'),{recursive:true});await cp('.tools/node-v22.22.1-linux-x64/bin/node',join(app,'runtime/node'));await chmod(join(app,'runtime/node'),0o755);
const files={
 'DEBIAN/control':`Package: g-collie\nVersion: ${version}\nSection: utils\nPriority: optional\nArchitecture: amd64\nMaintainer: Giggle\nDepends: libc6 (>= 2.28), libstdc++6, python3, systemd, xdg-utils, zlib1g\nDescription: Personal mobile console for local AI agents\n G-Collie desktop service and web interface. Developer beta.\n`,
 'usr/bin/g-collie':'#!/bin/sh\nexec /usr/lib/g-collie/runtime/node /usr/lib/g-collie/launcher.mjs "$@"\n',
 'usr/share/applications/g-collie.desktop':'[Desktop Entry]\nName=G-Collie\nComment=个人 AI Agent 工作台\nExec=g-collie open\nIcon=g-collie\nType=Application\nCategories=Development;Utility;\nTerminal=false\nStartupNotify=true\n',
 'usr/share/doc/g-collie/README':'G-Collie developer beta\nRun g-collie to start the current-user service and open the browser.\nData: ~/.local/share/g-collie (mode 700)\nStop: g-collie stop\nDisable autostart before package removal: g-collie uninstall-service\nNo accounts, conversations, device credentials or signing keys are shipped.\n'
};
for(const [p,s]of Object.entries(files)){await mkdir(join(stage,p,'..'),{recursive:true});await writeFile(join(stage,p),s);}
await chmod(join(stage,'usr/bin/g-collie'),0o755);
await mkdir(join(stage,'usr/share/icons/hicolor/512x512/apps'),{recursive:true});await cp('public/brand/collie-mark-v2.png',join(stage,'usr/share/icons/hicolor/512x512/apps/g-collie.png'));
await mkdir(join(stage,'usr/share/doc/g-collie/manual'),{recursive:true});for(const name of ['README.md','RELEASE.md','LICENSE','NOTICE','THIRD_PARTY_NOTICES.md'])await cp(name,join(stage,'usr/share/doc/g-collie',name));for(const name of ['电脑端使用说明.md','手机端使用说明.md','内置远程连接.md','能力矩阵.md'])await cp(join('docs',name),join(stage,'usr/share/doc/g-collie/manual',name));await cp('android/assets',join(stage,'usr/share/doc/g-collie/network-licenses'),{recursive:true});await cp('.tools/node-v22.22.1-linux-x64/LICENSE',join(stage,'usr/share/doc/g-collie/Node-LICENSE'));
await writeFile(join(stage,'usr/share/doc/g-collie/THIRD-PARTY.txt'),await readFile('public/icons/README.md','utf8'));
let notices='Bundled JavaScript dependency licenses\n';const packages=new Set();for(const input of Object.keys(bundled.metafile.inputs)){const m=input.match(/^node_modules\/((?:@[^/]+\/)?[^/]+)/);if(m)packages.add(m[1]);}for(const name of packages){const pkg=JSON.parse(await readFile(join('node_modules',name,'package.json'),'utf8'));notices+='\n--- '+name+' '+pkg.version+' ('+pkg.license+') ---\n';for(const file of ['LICENSE','LICENSE.md','LICENSE-MIT','license','LICENSE.txt','NOTICE','NOTICE.txt','NOTICE.md'])try{notices+='\n'+file+'\n'+await readFile(join('node_modules',name,file),'utf8')}catch{}}// Preserve repository-relative guide/image paths for offline package readers.
const docRoot=join(stage,'usr/share/doc/g-collie');
const guides=['电脑端使用说明.md','手机端使用说明.md','内置远程连接.md','能力矩阵.md'];
await mkdir(join(docRoot,'docs'),{recursive:true});
for(const name of guides)await cp(join('docs',name),join(docRoot,'docs',name));
for(const guide of ['README.md',...guides.map(name=>join('docs',name))]){
 const source=await readFile(guide,'utf8');
 for(const match of source.matchAll(/!\[[^\]]*\]\(([^)]+)\)/g)){
  const imagePath=resolve(guide,'..',match[1]);
  if(!imagePath.startsWith(join(root,'docs')+'/'))throw Error('Guide image must remain in docs');
  const relative=imagePath.slice(root.length+1);
  const destination=join(docRoot,relative);
  await mkdir(resolve(destination,'..'),{recursive:true});await cp(imagePath,destination);
  if(guide!=='README.md'){
   const legacy=join(docRoot,'manual',match[1]);
   await mkdir(resolve(legacy,'..'),{recursive:true});await cp(imagePath,legacy);
  }
 }
}
await writeFile(join(stage,'usr/share/doc/g-collie/JavaScript-LICENSES.txt'),notices);execFileSync('chmod',['-R','go-w',stage]);await mkdir('releases',{recursive:true});const output=`releases/g-collie_${version}_amd64.deb`;execFileSync('dpkg-deb',['--root-owner-group','--build',stage,output+'.tmp'],{stdio:'inherit'});await rename(output+'.tmp',output);
