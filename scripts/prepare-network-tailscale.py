"""Prepare a verified, disposable Android-only Tailscale source replacement."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
GO = os.environ.get('GCOLLIE_GO', str(ROOT / '.tools/go/bin/go'))
VERSION = 'v1.104.1'
EXPECTED_SHA256 = '94236cdfaf955f83cfb82ffaed8c913fa7d69b4b35c9549660fa600f5d4585df'
module = json.loads(subprocess.check_output(
    [GO, 'list', '-m', '-json', 'tailscale.com'], cwd=ROOT / 'network', text=True))
if module.get('Version') != VERSION or module.get('Replace'):
    raise SystemExit('Expected unreplaced tailscale.com ' + VERSION)
source = Path(module['Dir'])
relative = Path('net/dnscache/dnscache.go')
original = (source / relative).read_bytes()
if hashlib.sha256(original).hexdigest() != EXPECTED_SHA256:
    raise SystemExit('Tailscale dnscache source checksum mismatch; review patch before upgrading')
old = b'context.WithTimeout(ctx, 5*time.Second)'
if original.count(old) != 1:
    raise SystemExit('Expected exactly one TLS handshake timeout call')
output = ROOT / '.packaging/network'
output.mkdir(parents=True, exist_ok=True)
target = output / ('tailscale-' + VERSION)
if target.exists():
    for item in target.rglob('*'):
        if item.is_dir(): item.chmod(item.stat().st_mode | 0o700)
    target.chmod(target.stat().st_mode | 0o700)
    shutil.rmtree(target)
shutil.copytree(source, target)
target.chmod(target.stat().st_mode | 0o700)
for item in target.rglob('*'):
    item.chmod(item.stat().st_mode | (0o700 if item.is_dir() else 0o200))
(target / relative).write_bytes(original.replace(old, b'context.WithTimeout(ctx, gcollieTLSHandshakeTimeout(runtime.GOOS))'))
helper = ROOT / 'network/patches'
for name in ('gcollie_tls_timeout.go', 'gcollie_tls_timeout_test.go'):
    shutil.copyfile(helper / name, target / 'net/dnscache' / name)
modfile = output / 'android-network.mod'
modfile.write_text((ROOT / 'network/go.mod').read_text())
shutil.copyfile(ROOT / 'network/go.sum', modfile.with_suffix('.sum'))
subprocess.check_call([GO, 'mod', 'edit', '-modfile=' + str(modfile),
                       '-replace=tailscale.com=' + str(target)], cwd=ROOT / 'network')
(output / 'ANDROID-SOURCE-MODIFICATIONS.txt').write_text(
    'tailscale.com ' + VERSION + '\nOriginal net/dnscache/dnscache.go SHA256: ' + EXPECTED_SHA256 +
    '\nG-Collie modification: Android TLS handshake timeout 15 seconds; all other platforms 5 seconds.\n'
    'Earlier parent context deadlines and TLS certificate verification remain unchanged.\n'
    'Reproduce: python3 scripts/prepare-network-tailscale.py; scripts/build-network.sh\n')
print(modfile)
