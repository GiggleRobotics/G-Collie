#!/usr/bin/env python3
"""Verify production APKs and emit public metadata, never read signing secrets."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
if not sdk:
    props = (root / 'flutter_client/android/local.properties').read_text()
    sdk = re.search(r'^sdk.dir=(.+)$', props, re.M).group(1)
tools = max((Path(sdk) / 'build-tools').iterdir(), key=lambda p: tuple(int(x) for x in re.findall(r'\d+', p.name)))
java = str(Path(os.environ['JAVA_HOME']) / 'bin/java') if os.environ.get('JAVA_HOME') else 'java'
artifacts = []
for name in sys.argv[1:]:
    apk = Path(name).resolve()
    with zipfile.ZipFile(apk) as bundle:
        for asset in ['LICENSE.GCollie.txt', 'NOTICE.GCollie.txt', 'THIRD_PARTY_NOTICES.md', 'NETWORK-NOTICES.txt', 'AGENT-Codex-LICENSE.txt', 'AGENT-Hermes-LICENSE.txt', 'AGENT-provenance.json']:
            if not bundle.read('assets/flutter_assets/assets/' + asset):
                raise SystemExit('Missing release notice: ' + asset)
    cert = subprocess.check_output([java, '-jar', str(tools / 'lib/apksigner.jar'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
    if 'CN=Android Debug' in cert:
        raise SystemExit('Refusing debug certificate: ' + apk.name)
    fingerprints = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (.+)$', cert, re.M)
    if len(fingerprints) != 1:
        raise SystemExit('Expected one release signer: ' + apk.name)
    badging = subprocess.check_output([str(tools / 'aapt2'), 'dump', 'badging', str(apk)], text=True)
    if 'application-debuggable' in badging:
        raise SystemExit('Refusing debuggable APK: ' + apk.name)
    subprocess.run([str(tools / 'zipalign'), '-c', '-P', '16', '4', str(apk)], check=True)
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    abi = re.search(r"native-code: (.+)", badging).group(1).replace("'", '').split()
    if not package or package[1] != 'dev.giggle.g_collie_flutter':
        raise SystemExit('Unexpected package: ' + apk.name)
    artifacts.append({'file': apk.name, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                      'package': package[1], 'versionCode': int(package[2]), 'versionName': package[3],
                      'abi': abi, 'certificateSha256': fingerprints[0],
                      'debuggable': False, 'releaseNoticesVerified': True, 'apkSignatureVerified': True, 'zipAlignment16KiBVerified': True})
if not artifacts or len({x['certificateSha256'] for x in artifacts}) != 1 or len({x['versionName'] for x in artifacts}) != 1:
    raise SystemExit('Missing APKs or inconsistent release identity')
json.dump({'format': 1, 'artifacts': artifacts}, sys.stdout, indent=2)
print()
