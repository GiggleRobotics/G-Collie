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
# Bundle a complete Chinese fallback in the browser build; no external font CDN.
font = Path(os.environ.get('GCOLLIE_PREVIEW_CJK_FONT', '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf'))
if not font.exists(): raise RuntimeError('Set GCOLLIE_PREVIEW_CJK_FONT to a Chinese TTF font for offline preview')
(work/'assets/fonts').mkdir(parents=True, exist_ok=True)
shutil.copy2(font, work/'assets/fonts/prototype-cjk.ttf')
with (work/'pubspec.yaml').open('a') as f: f.write('\n  fonts:\n    - family: PrototypeCJK\n      fonts:\n        - asset: assets/fonts/prototype-cjk.ttf\n')

shutil.copytree(root/'flutter_client/assets',work/'assets',dirs_exist_ok=True)
shutil.copytree(root/'flutter_client/lib',work/'lib',dirs_exist_ok=True)
for path in adapters.glob('*.dart'): shutil.copy2(path,work/'lib'/path.name)
# The following sources must never be rewritten by the preview build.
manifest = {}
for src in sorted((root/'flutter_client/lib').glob('*.dart')):
    if src.name in ('api.dart','native.dart','ui.dart','connection_page.dart'): continue
    copied=work/'lib'/src.name
    assert src.read_bytes()==copied.read_bytes(), f'Widget source drift: {src}'
    manifest[src.name]=hashlib.sha256(src.read_bytes()).hexdigest()
run(sdk,'pub','get','--offline')
run(sdk,'build','web','--release','--target=lib/preview_main.dart','--base-href=/','--no-web-resources-cdn')
if out.exists(): shutil.rmtree(out)
shutil.copytree(work/'build/web',out)
license_path = Path('/usr/share/doc/fonts-droid-fallback/copyright')
if license_path.exists(): shutil.copy2(license_path, out/'PrototypeCJK-LICENSE.txt')
# Use content-specific filenames so preview refreshes cannot reuse an older UI.
revision = hashlib.sha256((out/'main.dart.js').read_bytes()).hexdigest()[:12]
main_name = f'main.{revision}.dart.js'
shutil.copy2(out/'main.dart.js', out/main_name)
bootstrap = (out/'flutter_bootstrap.js').read_text().replace('main.dart.js', main_name)
bootstrap = bootstrap[:bootstrap.rfind('_flutter.loader.load(')] + '_flutter.loader.load({});\n'
bootstrap_name = f'flutter_bootstrap.{revision}.js'
(out/bootstrap_name).write_text(bootstrap)
index=out/'index.html'
index.write_text(index.read_text().replace('<base href="/">','<base href="./">').replace('flutter_bootstrap.js',bootstrap_name))
(root/'docs/开发/交互原型/source-manifest.json').write_text(json.dumps({'source':'flutter_client/lib','git_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'pubspec_sha256':hashlib.sha256((root/'flutter_client/pubspec.yaml').read_bytes()).hexdigest(),'unchanged_widget_sources_sha256':manifest,'adapters':sorted(path.name for path in adapters.glob('*.dart')),'prototype_ui_note':'Prototype-only UI changes include session filters, quota notices, home composer visibility and multi-computer pairing/selection. Production UI is unchanged.','note':'Shared widget source identity; Android system UI still requires device verification.'},ensure_ascii=False,indent=2)+'\n')
print(f'Preview: {out}/index.html')
