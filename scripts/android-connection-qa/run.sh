#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
qa_root="$PWD/.packaging/connection-qa"
qa_sdk="${ANDROID_HOME:-$PWD/.tools/android-sdk}"
qa_jdk="${JAVA_HOME:-$PWD/.tools/gcollie-jdk}"
qa_adb="$qa_sdk/platform-tools/adb"
qa_serial="${GCOLLIE_ADB_SERIAL:?Set GCOLLIE_ADB_SERIAL to the authorized unlocked test phone}"
qa_tools="$qa_sdk/build-tools/36.0.0"
qa_android="$qa_sdk/platforms/android-36/android.jar"
mkdir -p "$qa_root/classes" "$qa_root/dex"
"$qa_jdk/bin/javac" -source 17 -target 17 -cp "$qa_android" -d "$qa_root/classes" scripts/android-connection-qa/ConnectionChecks.java
"$qa_jdk/bin/java" -cp "$qa_tools/lib/d8.jar" com.android.tools.r8.D8 --lib "$qa_android" --output "$qa_root/dex" "$qa_root/classes/dev/giggle/qa/ConnectionChecks.class"
"$qa_tools/aapt2" link -I "$qa_android" --manifest scripts/android-connection-qa/AndroidManifest.xml -o "$qa_root/test.apk"
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('.packaging/connection-qa/test.apk','a') as package:
    package.write('.packaging/connection-qa/dex/classes.dex','classes.dex')
PY
"$qa_jdk/bin/java" -jar "$qa_tools/lib/apksigner.jar" sign --ks "${GCOLLIE_QA_KEYSTORE:-$HOME/.android/debug.keystore}" --ks-pass pass:android "$qa_root/test.apk"
cleanup() {
  "$qa_adb" -s "$qa_serial" shell am force-stop dev.giggle.g_collie_flutter >/dev/null || true
  "$qa_adb" -s "$qa_serial" uninstall dev.giggle.connectionqa >/dev/null || true
  "$qa_adb" -s "$qa_serial" shell am start -n dev.giggle.g_collie_flutter/.MainActivity >/dev/null || true
}
trap cleanup EXIT
"$qa_adb" -s "$qa_serial" install --no-incremental -r "$qa_root/test.apk"
"$qa_adb" -s "$qa_serial" shell am instrument -w dev.giggle.connectionqa/dev.giggle.qa.ConnectionChecks | tee "$qa_root/result.txt"
rg -q '^PASS native notification' "$qa_root/result.txt"
