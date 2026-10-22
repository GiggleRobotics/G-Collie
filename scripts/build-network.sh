#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../network"
GO="${GCOLLIE_GO:-$PWD/../.tools/go/bin/go}"
NDK="${GCOLLIE_ANDROID_NDK:-$PWD/../.tools/android-ndk-r27d}"
export GOMAXPROCS=4
export GODEBUG=http2client=0
TAGS="ts_omit_ssh,ts_omit_taildrop,ts_omit_webclient"
mkdir -p ../.packaging/network ../android/lib/arm64-v8a ../android/lib/x86_64
"$GO" test -tags "$TAGS" -p 4 ./core
CGO_ENABLED=0 "$GO" build -tags "$TAGS" -p 4 -trimpath -ldflags='-s -w' -o ../.packaging/network/g-collie-network ./cmd/gcollie-network
CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang" "$GO" build -tags "$TAGS" -p 4 -trimpath -buildmode=c-shared -ldflags='-s -w -extldflags=-Wl,-z,max-page-size=16384' -o ../android/lib/arm64-v8a/libgcollie_network.so ./mobile
CGO_ENABLED=1 GOOS=android GOARCH=amd64 CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang" "$GO" build -tags "$TAGS" -p 4 -trimpath -buildmode=c-shared -ldflags='-s -w -extldflags=-Wl,-z,max-page-size=16384' -o ../android/lib/x86_64/libgcollie_network.so ./mobile
"$GO" version -m ../.packaging/network/g-collie-network > ../.packaging/network/build-info.txt

python3 ../scripts/network-licenses.py
