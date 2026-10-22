#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_cmd="${GCOLLIE_FLUTTER:-flutter}"
for arch in arm64-v8a x86_64; do
  test -f "android/lib/$arch/libgcollie_network.so" || { echo '请先运行 npm run build:network，生成现有内置网络模块。' >&2; exit 1; }
done
cd flutter_client
app_version="$(awk '/^version:/ {split($2, parts, "+"); print parts[1]}' pubspec.yaml)"
artifact="g-collie-flutter-${app_version}-arm64-beta.apk"
"$flutter_cmd" pub get
"$flutter_cmd" analyze
"$flutter_cmd" test
"$flutter_cmd" build apk --release --target-platform android-arm64 --split-per-abi
mkdir -p ../releases
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "../releases/$artifact"
(
  cd ../releases
  sha256sum "$artifact" > "$artifact.sha256"
)
echo "已生成 releases/$artifact（内测签名）"
