#!/usr/bin/env python3
"""Build a browser preview from the exact production Flutter widget sources."""
from pathlib import Path
import hashlib, json, os, shutil, subprocess
root = Path(__file__).resolve().parents[1]
sdk = os.environ.get('GCOLLIE_FLUTTER', 'flutter')
work = root / '.packaging/flutter-ui-prototype'
out = root / 'docs/开发/交互原型/flutter'
adapters = root / 'docs/开发/交互原型/adapters'
work.mkdir(parents=True, exist_ok=True)
def run(*args): subprocess.run(args, cwd=work, check=True)
if not (work / 'web/index.html').exists():
    run(sdk, 'create', '--platforms=web', '--project-name=g_collie_flutter', '--no-pub', '.')
shutil.copy2(root/'flutter_client/pubspec.yaml',work/'pubspec.yaml')
shutil.copy2(root/'flutter_client/pubspec.lock',work/'pubspec.lock')
shutil.copytree(root/'flutter_client/assets',work/'assets',dirs_exist_ok=True)
shutil.copytree(root/'flutter_client/lib',work/'lib',dirs_exist_ok=True)
for path in adapters.glob('*.dart'): shutil.copy2(path,work/'lib'/path.name)
# The following sources must never be rewritten by the preview build.
manifest = {}
for src in sorted((root/'flutter_client/lib').glob('*.dart')):
    if src.name in ('api.dart','native.dart'): continue
    copied=work/'lib'/src.name
    assert src.read_bytes()==copied.read_bytes(), f'Widget source drift: {src}'
    manifest[src.name]=hashlib.sha256(src.read_bytes()).hexdigest()
run(sdk,'pub','get','--offline')
run(sdk,'build','web','--release','--target=lib/preview_main.dart','--base-href=/','--no-web-resources-cdn')
if out.exists(): shutil.rmtree(out)
shutil.copytree(work/'build/web',out)
index=out/'index.html'
index.write_text(index.read_text().replace('<base href="/">','<base href="./">'))
(root/'docs/开发/交互原型/source-manifest.json').write_text(json.dumps({'source':'flutter_client/lib','git_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'pubspec_sha256':hashlib.sha256((root/'flutter_client/pubspec.yaml').read_bytes()).hexdigest(),'unchanged_widget_sources_sha256':manifest,'adapters':['api.dart','native.dart','preview_main.dart'],'note':'Shared widget source identity; Android system UI still requires device verification.'},ensure_ascii=False,indent=2)+'\n')
print(f'Preview: {out}/index.html')
