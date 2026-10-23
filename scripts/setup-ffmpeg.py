"""Install a pinned, hash-verified imageio-ffmpeg wheel binary locally (no pip)."""
import hashlib,json,pathlib,stat,urllib.request,zipfile,io
root=pathlib.Path(__file__).resolve().parent.parent/'.tools/ffmpeg'
root.mkdir(parents=True,exist_ok=True)
metadata=json.load(urllib.request.urlopen('https://pypi.org/pypi/imageio-ffmpeg/0.6.0/json'))
wheel=next(x for x in metadata['urls'] if x['filename'].endswith('manylinux2014_x86_64.whl'))
data=urllib.request.urlopen(wheel['url'],timeout=60).read()
if hashlib.sha256(data).hexdigest()!=wheel['digests']['sha256']:raise RuntimeError('FFmpeg wheel checksum mismatch')
with zipfile.ZipFile(io.BytesIO(data)) as z:
 binary=next(n for n in z.namelist() if '/binaries/ffmpeg-' in n and not n.endswith('.md'))
 (root/'ffmpeg').write_bytes(z.read(binary));(root/'ffmpeg').chmod(0o755)
 for n in z.namelist():
  if 'license' in n.lower() or n.lower().endswith('copying'): (root/pathlib.PurePosixPath(n).name).write_bytes(z.read(n))
(root/'source.json').write_text(json.dumps({'project':'imageio-ffmpeg','version':'0.6.0','wheel':wheel['filename'],'sha256':wheel['digests']['sha256']}))
print('Installed local FFmpeg with verified wheel hash')
