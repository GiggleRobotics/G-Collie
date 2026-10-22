import{readFileSync}from'node:fs';import{execFileSync}from'node:child_process';
if(Number(process.versions.node.split('.')[0])<22)throw Error('需要 Node.js 22 或更高版本');execFileSync('npm',['ci'],{stdio:'inherit'});execFileSync('npm',['run','build'],{stdio:'inherit'});console.log('构建完成。Linux：npm run service:install，然后 npm run service:start；前台：npm start。');
