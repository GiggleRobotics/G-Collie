"""Collect the notices for linked Go modules; never collect state or credentials."""
import json,pathlib,subprocess,os
root=pathlib.Path(__file__).resolve().parent.parent
go=os.environ.get('GCOLLIE_GO',str(root/'.tools/go/bin/go'))
raw=subprocess.check_output([go,'list','-tags','ts_omit_ssh,ts_omit_taildrop,ts_omit_webclient','-deps','-json','./cmd/gcollie-network','./core'],cwd=root/'network',text=True)
decoder=json.JSONDecoder();modules={};pos=0
while pos<len(raw):
 while pos<len(raw) and raw[pos].isspace():pos+=1
 if pos>=len(raw):break
 obj,end=decoder.raw_decode(raw,pos);pos=end
 m=obj.get('Module',{});m=m.get('Replace',m)
 if m.get('Dir') and not m.get('Main'):modules[m['Path']]=m
out=['G-Collie embedded network: third-party notices\n','Go runtime\n'+(root/'.tools/go/LICENSE').read_text()]
for name,m in sorted(modules.items()):
 p=pathlib.Path(m['Dir']);out.append('\n=== '+name+' '+m.get('Version','')+' ===\n')
 for f in sorted(p.iterdir()):
  if f.is_file() and f.name.upper().startswith(('LICENSE','COPYING','NOTICE','PATENTS')):
   out.append('\n'+f.name+'\n'+f.read_text(errors='replace'))
assets=root/'android/assets';assets.mkdir(parents=True,exist_ok=True)
(assets/'NETWORK-NOTICES.txt').write_text('\n'.join(out))
print('Network notices collected:',len(modules),'modules')
