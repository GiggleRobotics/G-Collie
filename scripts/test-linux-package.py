"""Smoke-test an extracted DEB in a disposable HOME, without installing or touching services.
Usage: python3 scripts/test-linux-package.py /path/to/dpkg-deb-extracted-root
The test binds loopback only and never sends to real Agent sessions.
"""
import os, sys, pathlib, subprocess, socket, time, json, urllib.request, urllib.error, tempfile, re
root=pathlib.Path(sys.argv[1]).resolve(); app=root/'usr/lib/g-collie'
results={}
def binary(name,args):
 p=subprocess.run([str(app/name)]+args,capture_output=True,text=True,timeout=15)
 assert p.returncode==0,(name,p.returncode,p.stderr[-1500:])
 results[str(name)]=(p.stdout+p.stderr).splitlines()[:2]
binary(pathlib.Path('runtime/node'),['--version']);binary(pathlib.Path('ffmpeg'),['-version']);binary(pathlib.Path('g-collie-network'),['--help'])
with tempfile.TemporaryDirectory(prefix='gcollie-smoke-state.') as folder:
 h=pathlib.Path(folder); home=h/'home';home.mkdir();data=h/'data'
 def media(args):
  subprocess.run([str(app/'ffmpeg'),'-hide_banner','-loglevel','error','-nostdin','-threads','1']+args,check=True,timeout=20,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 media(['-f','lavfi','-i','color=c=blue:s=160x120','-frames:v','1',str(h/'photo.png')])
 media(['-i',str(h/'photo.png'),'-frames:v','1','-vf','scale=2048:2048:force_original_aspect_ratio=decrease','-q:v','3',str(h/'photo.jpg')])
 media(['-f','lavfi','-i','color=c=blue:s=160x120:d=0.2','-c:v','mpeg4','-pix_fmt','yuv420p',str(h/'clip.mp4')])
 media(['-i',str(h/'clip.mp4'),'-frames:v','1','-vf','scale=960:960:force_original_aspect_ratio=decrease','-q:v','4',str(h/'poster.jpg')])
 assert (h/'photo.jpg').stat().st_size>0 and (h/'poster.jpg').stat().st_size>0
 results['media']='native PNG generation, PNG->JPEG scaling, MPEG4 video decoding/poster passed'
 sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
 env=dict(os.environ,HOME=str(home),CODEX_HOME=str(home/'.codex'),XDG_CONFIG_HOME=str(home/'.config'),GCOLLIE_DATA_DIR=str(data),NODE_ENV='production',HOST='127.0.0.1',PORT=str(port),ORBIT_DESKTOP_CONTROL='0',ORBIT_CODEX_BIN='/bin/false',GCOLLIE_CLAUDE_BIN='/bin/false',GCOLLIE_NETWORK_BINARY='/bin/false')
 with (h/'server.log').open('w+') as log:
  proc=subprocess.Popen([str(app/'runtime/node'),str(app/'launcher.mjs'),'serve'],cwd=str(app),env=env,stdout=log,stderr=log)
  base='http://127.0.0.1:'+str(port)
  def req(path,body=None,headers=None):
   q=urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers=dict({'Content-Type':'application/json'},**(headers or {})))
   try:
    with urllib.request.urlopen(q,timeout=25) as r:return r.status,r.read(),r.headers
   except urllib.error.HTTPError as e:return e.code,e.read(),e.headers
  try:
   for i in range(100):
    if proc.poll() is not None:log.seek(0);raise AssertionError(log.read())
    try:
     if req('/healthz')[0]==200:break
    except OSError:pass
    time.sleep(.15)
   status,body,_=req('/healthz');assert status==200;results['health']=json.loads(body)
   status,index,_=req('/');assert status==200
   assets=re.findall(r'(?:src|href)="(/assets/[^"]+)"',index.decode());assert assets
   for asset in assets:
    status,body,headers=req(asset);assert status==200 and body and 'text/html' not in headers.get('Content-Type',''),asset
   results['static_assets']=len(assets)
   assert req('/api/local')[0]==401
   token=(data/'access-token').read_text().strip()
   status,body,headers=req('/api/auth/exchange',{'name':'isolated release QA'},{'Authorization':'Bearer '+token});assert status==200,(status,body)
   cookie=headers.get('Set-Cookie').split(';')[0];auth={'Cookie':cookie}
   for path in ['/api/local','/api/adapters','/api/schedules','/api/devices','/api/network/embedded','/api/usage']:
    status,body,_=req(path,headers=auth);assert status==200,(path,status,body[:500]);results[path]='200 JSON';json.loads(body)
   status,body,_=req('/api/devices/pair',{'origin':base},auth);assert status==200;(code,)= (json.loads(body)['code'],)
   status,body,headers=req('/api/auth/pair',{'code':code,'name':'isolated phone'});assert status==200;phone=json.loads(body);pc={'Cookie':headers.get('Set-Cookie').split(';')[0]}
   assert req('/api/devices',headers=pc)[0]==403
   assert req('/api/local',headers=pc)[0]==200
   assert req('/api/devices/'+phone['device']['id']+'/revoke',{},auth)[0]==200
   assert req('/api/local',headers=pc)[0]==401
   results['auth']='owner exchange, temporary pair, phone read, owner boundary, revoke passed'
   assert oct((data/'access-token').stat().st_mode & 0o777)=='0o600';results['token_mode']='0600'
  finally:
   if sys.exc_info()[0] is not None:
    log.flush();log.seek(0);print(log.read()[-5000:],flush=True)
   proc.terminate()
   try:proc.wait(timeout=10)
   except subprocess.TimeoutExpired:proc.kill();proc.wait()
print(json.dumps(results,ensure_ascii=False,indent=2))
