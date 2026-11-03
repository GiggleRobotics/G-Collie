import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {ffmpeg} from './claude-media.js';
import {videoPoster} from './video-poster.js';
test('video poster extracts an actual frame and coalesces concurrent requests',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'gcollie-poster-')),previous=process.env.GCOLLIE_DATA_DIR;process.env.GCOLLIE_DATA_DIR=dir;
 try{
  const path=join(dir,'clip.mp4');execFileSync(ffmpeg(),['-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=blue:s=160x90','-t','0.2','-pix_fmt','yuv420p','-y',path]);
  const st=await stat(path),file={path,extension:'.mp4',size:st.size,mtime:st.mtimeMs};
  const [a,b]=await Promise.all([videoPoster(file),videoPoster(file)]);assert.equal(a,b);assert.equal((await readFile(a)).subarray(0,2).toString('hex'),'ffd8');
  await assert.rejects(videoPoster({...file,extension:'.txt'}));
 }finally{if(previous===undefined)delete process.env.GCOLLIE_DATA_DIR;else process.env.GCOLLIE_DATA_DIR=previous;await rm(dir,{recursive:true,force:true})}
});
