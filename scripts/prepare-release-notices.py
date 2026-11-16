"""Copy public license material only; never read signing files or runtime state."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
assets = root / 'flutter_client/assets'
for source, name in [
    ('LICENSE', 'LICENSE.GCollie.txt'),
    ('NOTICE', 'NOTICE.GCollie.txt'),
    ('THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md'),
    ('android/assets/NETWORK-NOTICES.txt', 'NETWORK-NOTICES.txt'),
]:
    path = root / source
    if not path.is_file():
        raise SystemExit('Required public notice missing: ' + source)
    shutil.copyfile(path, assets / name)
for path in (root / 'public/icons/licenses').iterdir():
    if path.is_file():
        shutil.copyfile(path, assets / ('AGENT-' + path.name))
print('Prepared project, network and integration-asset license material for APK.')
