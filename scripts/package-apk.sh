#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
JAVA="${GCOLLIE_JAVA:-${JAVA_HOME:+$JAVA_HOME/bin/java}}"
JAVA="${JAVA:-$PWD/.tools/jre/bin/java}"
TOOLS="${GCOLLIE_ANDROID_BUILD_TOOLS:-$PWD/.tools/android-15}"
PLATFORM="${GCOLLIE_ANDROID_PLATFORM:-$PWD/.tools/android-35/android.jar}"
VERSION="$(node -p "require('./package.json').version")"
BUILD="$PWD/.packaging/android"
test -f android/lib/arm64-v8a/libgcollie_network.so || { echo "先运行 npm run build:network" >&2; exit 1; }
rm -rf "$BUILD/classes" "$BUILD/dex"
mkdir -p "$BUILD/classes" "$BUILD/dex" releases
"$JAVA" -jar .tools/ecj.jar -source 1.8 -target 1.8 -proc:none -warn:none -classpath "$PLATFORM" -d "$BUILD/classes" android/src/dev/giggle/gcollie/*.java
"$JAVA" -cp "$TOOLS/lib/d8.jar" com.android.tools.r8.D8 --min-api 26 --lib "$PLATFORM" --output "$BUILD/dex" "$BUILD"/classes/dev/giggle/gcollie/*.class
"$TOOLS/aapt2" compile --dir android/res -o "$BUILD/resources.zip"
"$TOOLS/aapt2" link -o "$BUILD/unsigned.apk" -I "$PLATFORM" --manifest android/AndroidManifest.xml "$BUILD/resources.zip"
python3 - "$BUILD" <<'PY'
import zipfile,sys
from pathlib import Path
b=Path(sys.argv[1])
with zipfile.ZipFile(b/'unsigned.apk','a') as z:
 z.write(b/'dex/classes.dex','classes.dex')
 for lib in Path('android/lib').glob('*/libgcollie_network.so'):z.write(lib,'lib/'+lib.parent.name+'/'+lib.name)
 for p in Path('android/assets').glob('*'):z.write(p,'assets/'+p.name)
PY
"$TOOLS/zipalign" -f -P 16 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"
KEYDIR="${XDG_DATA_HOME:-$HOME/.local/share}/g-collie-signing"
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
if [ ! -f "$KEYDIR/android-beta.p12" ]; then
  umask 077
  head -c 32 /dev/urandom | base64 > "$KEYDIR/password"
  "$(dirname "$JAVA")/keytool" -genkeypair -keystore "$KEYDIR/android-beta.p12" -storetype PKCS12 -storepass:file "$KEYDIR/password" -alias g-collie -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=G-Collie Developer Beta, O=Giggle'
fi
"$JAVA" -jar "$TOOLS/lib/apksigner.jar" sign --ks "$KEYDIR/android-beta.p12" --ks-pass "file:$KEYDIR/password" --ks-key-alias g-collie --out releases/g-collie-${VERSION}-android.apk "$BUILD/aligned.apk"
"$JAVA" -jar "$TOOLS/lib/apksigner.jar" verify --verbose --print-certs releases/g-collie-${VERSION}-android.apk
