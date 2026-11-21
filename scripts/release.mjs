// Source snapshot matches the working tree used for binaries, not an older Git HEAD.
import {execFileSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
const version=JSON.parse(readFileSync('package.json','utf8')).version;
mkdirSync('releases',{recursive:true});
const archive=`releases/g-collie-${version}-source.tar.gz`;
const inputs=['LICENSE','NOTICE','THIRD_PARTY_NOTICES.md','README.md','CONTRIBUTING.md','TESTING.md','RELEASE.md','package.json','package-lock.json','tsconfig.json','vite.config.ts','index.html','server','web','public','scripts','network','android','flutter_client','docs'].filter(existsSync);
const excludes=['AGENTS.md','.codex','.idea','.vscode','*.log','docs/开发/问题视频','docs/开发/发布验收','.env','.env.*','.data','*.jks','*.keystore','*.p12','*.key','signing.properties','key.properties','local.properties','.git','.gradle','.dart_tool','build','node_modules','__pycache__','*.pyc','android/lib','flutter_client/android/app/src/main/jniLibs','docs/开发/问题截图','docs/开发/交互原型/flutter','*.mp4','*.webm','*.apk','*.deb'];
execFileSync('tar',['-czf',archive,...excludes.map(v=>'--exclude='+v),...inputs],{stdio:'inherit'});
writeFileSync(archive+'.sha256',createHash('sha256').update(readFileSync(archive)).digest('hex')+'  '+archive.split('/').at(-1)+'\n');
console.log(archive);
