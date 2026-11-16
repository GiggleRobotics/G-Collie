#!/usr/bin/env python3
"""Read-only release artifact gate; never reads signing keys or starts app services."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def checksums(path):
    result = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  ([^/]+)', line)
        require(match is not None, 'Invalid checksum entry in ' + path.name)
        require(match[2] not in result, 'Duplicate checksum entry')
        result[match[2]] = match[1]
    return result


def safe_source(member):
    path = PurePosixPath(member.name)
    require(not path.is_absolute() and '..' not in path.parts, 'Unsafe source path: ' + member.name)
    forbidden = {'.git', '.ssh', '.data', '.gradle', '.dart_tool', 'node_modules', '__pycache__', 'local.properties', 'key.properties', 'signing.properties'}
    require(not forbidden.intersection(path.parts), 'Private/generated source entry: ' + member.name)
    require(not any(p == '.env' or p.startswith('.env.') for p in path.parts), 'Environment file in source')
    require(path.suffix.lower() not in {'.jks', '.keystore', '.p12', '.key', '.apk', '.deb', '.pyc'}, 'Private/generated source suffix: ' + member.name)
    require(not member.issym() and not member.islnk() and (member.isfile() or member.isdir()), 'Unexpected source entry type: ' + member.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--releases', type=Path, default=ROOT / 'releases')
    args = parser.parse_args()
    release = args.releases.resolve()
    version = json.loads((ROOT / 'package.json').read_text())['version']
    mobile_version = re.search(r'^version: ([^+\s]+)', (ROOT / 'flutter_client/pubspec.yaml').read_text(), re.M).group(1)
    android = json.loads((release / ('g-collie-' + mobile_version + '-android-signatures.json')).read_text())
    apks = android['artifacts']
    require(len(apks) == 2, 'Expected both Android ABIs')
    source_name = 'g-collie-' + version + '-source.tar.gz'
    deb_name = 'g-collie_' + version + '_amd64.deb'
    names = {source_name, deb_name, *(a['file'] for a in apks)}
    manifest = checksums(release / 'SHA256SUMS-first-release')
    require(set(manifest) == names, 'Release checksum set differs from four production artifacts')
    for name in sorted(names):
        require(digest(release / name) == manifest[name], 'SHA256 mismatch: ' + name)
        require(checksums(release / (name + '.sha256')) == {name: manifest[name]}, 'Per-file checksum mismatch: ' + name)
    with tarfile.open(release / source_name, 'r:gz') as archive:
        members = archive.getmembers()
        for member in members:
            safe_source(member)
            if member.isfile() and member.size < 4 * 1024 * 1024:
                content = archive.extractfile(member).read()
                require(not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----\s+[A-Za-z0-9+/=]{40}', content), 'Private key material: ' + member.name)
        paths = {m.name for m in members if m.isfile()}
        required = {'LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md', 'package.json', 'package-lock.json', 'network/go.mod', 'network/go.sum', 'flutter_client/pubspec.lock', 'scripts/package-deb.mjs', 'scripts/package-flutter-apk.sh', 'scripts/path_compat.py', 'scripts/build-release-ffmpeg.sh', 'public/icons/licenses/Codex-LICENSE.txt', 'public/icons/licenses/Hermes-LICENSE.txt'}
        require(required <= paths, 'Missing corresponding source inputs: ' + ', '.join(sorted(required - paths)))
        require(json.loads(archive.extractfile('package.json').read())['version'] == version, 'Source version mismatch')
        source = {p: archive.extractfile(p).read() for p in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md', 'android/assets/NETWORK-NOTICES.txt', 'public/icons/licenses/Codex-LICENSE.txt', 'public/icons/licenses/Hermes-LICENSE.txt', 'public/icons/licenses/provenance.json']}
    asset_sources = {'LICENSE.GCollie.txt': 'LICENSE', 'NOTICE.GCollie.txt': 'NOTICE', 'THIRD_PARTY_NOTICES.md': 'THIRD_PARTY_NOTICES.md', 'NETWORK-NOTICES.txt': 'android/assets/NETWORK-NOTICES.txt', 'AGENT-Codex-LICENSE.txt': 'public/icons/licenses/Codex-LICENSE.txt', 'AGENT-Hermes-LICENSE.txt': 'public/icons/licenses/Hermes-LICENSE.txt', 'AGENT-provenance.json': 'public/icons/licenses/provenance.json'}
    require(len({a['certificateSha256'] for a in apks}) == 1, 'Android signer mismatch')
    require({tuple(a['abi']) for a in apks} == {('arm64-v8a',), ('x86_64',)}, 'Android ABI set mismatch')
    for apk in apks:
        require(apk['sha256'] == manifest[apk['file']], 'Android metadata hash mismatch')
        require(apk['package'] == 'dev.giggle.g_collie_flutter' and apk['debuggable'] is False, 'Android package/debug metadata invalid')
        require(all(apk.get(k) is True for k in ['releaseNoticesVerified', 'apkSignatureVerified', 'zipAlignment16KiBVerified']), 'Incomplete Android verification metadata')
        with zipfile.ZipFile(release / apk['file']) as bundle:
            for name, origin in asset_sources.items():
                require(bundle.read('assets/flutter_assets/assets/' + name) == source[origin], 'APK notice differs from source: ' + name)
            actual_abis = {PurePosixPath(p).parts[1] for p in bundle.namelist() if p.startswith('lib/') and p.endswith('.so')}
            require(actual_abis == set(apk['abi']), 'APK native ABI differs from metadata')
    actual_version = subprocess.check_output(['dpkg-deb', '-f', str(release / deb_name), 'Version'], text=True).strip()
    require(actual_version == version, 'DEB version mismatch')
    with tempfile.TemporaryDirectory(prefix='gcollie-release-gate-') as temp:
        subprocess.run(['dpkg-deb', '-x', str(release / deb_name), temp], check=True)
        doc = Path(temp) / 'usr/share/doc/g-collie'
        for name in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md']:
            require((doc / name).read_bytes() == source[name], 'DEB notice differs from source: ' + name)
        for name in ['Node-LICENSE', 'JavaScript-LICENSES.txt', 'network-licenses/NETWORK-NOTICES.txt', 'ffmpeg/ffmpeg-7.0.2.tar.xz', 'ffmpeg/build.sh', 'ffmpeg/COPYING.LGPLv2.1', 'ffmpeg/source.json']:
            require((doc / name).is_file() and (doc / name).stat().st_size, 'Missing DEB corresponding license/source: ' + name)
        ffmpeg = json.loads((doc / 'ffmpeg/source.json').read_text())
        # Provenance key names are intentionally read without invoking the bundled binary.
        require(digest(doc / 'ffmpeg/ffmpeg-7.0.2.tar.xz') in json.dumps(ffmpeg), 'FFmpeg source provenance hash mismatch')
    print(json.dumps({'result': 'PASS', 'desktopVersion': version, 'artifacts': manifest, 'sourceEntries': len(members), 'checks': ['four artifact hashes and individual manifests', 'source path/type/private-key gate', 'required corresponding source inputs', 'APK legal contents and native ABI against public metadata', 'DEB version/legal notices/FFmpeg corresponding source'], 'limits': ['does not reverify APK cryptographic signatures; use verify-android-release.py', 'does not prove absence of arbitrary personal text or runtime compatibility']}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, tarfile.TarError, zipfile.BadZipFile) as error:
        raise SystemExit('FAIL: ' + str(error))
