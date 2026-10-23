import {test} from 'node:test';import assert from 'node:assert/strict';
import {mkdtemp,mkdir,symlink,rm,readFile} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';
import {FolderProjects} from './projects.js';
test('电脑文件夹只浏览普通用户目录；创建不覆盖，拒绝穿越、隐藏目录和外部符号链接',async()=>{
 const root=await mkdtemp(join(tmpdir(),'gcollie-projects-')),home=join(root,'home'),data=join(root,'data');await mkdir(home);await mkdir(data);await mkdir(join(home,'.private'));await symlink(data,join(home,'outside'));
 try{const p=new FolderProjects(data,home);const created=await p.createFolder(home,'中文项目');assert.equal(created.path,join(home,'中文项目'));
 const b=await p.browse();assert.deepEqual(b.folders.map(f=>f.name),['中文项目']);assert.equal(b.parent,null);
 await assert.rejects(p.createFolder(home,'中文项目'));await assert.rejects(p.createFolder(home,'../oops'));
 await assert.rejects(p.folder(join(home,'.private')));await assert.rejects(p.folder(join(home,'outside')));await assert.rejects(p.folder(data));
 const added=await p.add(created.path);assert.equal(added.name,'中文项目');assert.equal(await p.contains(created.path),true);
 await p.assign('native-thread',created.path);assert.equal(JSON.parse(await readFile(join(data,'folder-session-projects.json'),'utf8'))['native-thread'],created.path);
 await Promise.all([p.add(created.path,'新名称'),p.add(home,'用户目录')]);assert.equal((await p.list()).length,2);
 assert.equal((new FolderProjects(data,home)).contains(created.path) instanceof Promise,true);
 const content=JSON.parse(await readFile(join(data,'folder-projects.json'),'utf8'));assert.equal(content.length,2);
 }finally{await rm(root,{recursive:true,force:true})}
});
