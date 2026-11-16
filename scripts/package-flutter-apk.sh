#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_cmd="${GCOLLIE_FLUTTER:-flutter}"
if [[ -z "${GCOLLIE_ANDROID_SIGNING_PROPERTIES:-}" || ! -f "$GCOLLIE_ANDROID_SIGNING_PROPERTIES" ]]; then
  echo '正式 APK 必须设置 GCOLLIE_ANDROID_SIGNING_PROPERTIES，禁止使用 debug 签名。详见 flutter_client/README.md。' >&2
  exit 1
fi
for arch in arm64-v8a x86_64; do
  test -f "android/lib/$arch/libgcollie_network.so" || { echo '请先运行 npm run build:network，生成现有内置网络模块。' >&2; exit 1; }
done
python3 scripts/prepare-release-notices.py
cd flutter_client
app_version="$(awk '/^version:/ {split($2, parts, "+"); print parts[1]}' pubspec.yaml)"
# Release notices may be newly added directory assets; discard stale Flutter/Gradle asset bundles.
"$flutter_cmd" clean
"$flutter_cmd" pub get
"$flutter_cmd" analyze
"$flutter_cmd" test
"$flutter_cmd" build apk --release --target-platform android-arm64,android-x64 --split-per-abi
mkdir -p ../releases
for pair in 'arm64-v8a:arm64' 'x86_64:x86_64'; do
  abi="${pair%%:*}"
  artifact="g-collie-${app_version}-android-${pair##*:}-release.apk"
  cp "build/app/outputs/flutter-apk/app-${abi}-release.apk" "../releases/$artifact"
  (cd ../releases && sha256sum "$artifact" > "$artifact.sha256")
  echo "已生成 releases/$artifact（正式签名；x86_64 用于模拟器验证）"
done
python3 ../scripts/verify-android-release.py \
  "../releases/g-collie-${app_version}-android-arm64-release.apk" \
  "../releases/g-collie-${app_version}-android-x86_64-release.apk" \
  > "../releases/g-collie-${app_version}-android-signatures.json"
