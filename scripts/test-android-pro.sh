#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRO_HOST=jackwallner@192.168.4.25

rsync -az --delete \
    --exclude build --exclude .gradle --exclude .kotlin \
    --exclude local.properties --exclude verification --exclude captures --exclude '*.p12' --exclude '*.jks' --exclude '*.keystore' \
    "$REPO_DIR/android/" "$PRO_HOST:tmp/sol-recharge/android/"

ssh "$PRO_HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
export JAVA_HOME="$HOME/.jdk/jdk-21.0.12.1+1/Contents/Home"
export PATH="$JAVA_HOME/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
export ANDROID_SERIAL=emulator-5582
AVD_NAME=$(adb -s "$ANDROID_SERIAL" emu avd name </dev/null | tr -d '\r' | head -1)
test "$AVD_NAME" = sol-recharge
ACTIVITY=$(adb -s "$ANDROID_SERIAL" shell -n service check activity)
test "$ACTIVITY" = 'Service activity: found'
cd "$HOME/tmp/sol-recharge/android"
APP_PACKAGE=$(python3 -c 'from pathlib import Path; import re; print(re.search(r"applicationId = \"([^\"]+)\"", Path("app/build.gradle.kts").read_text()).group(1))')
# This temporary AVD and any debug installation belong to this run.
INSTALLED_APK=$(adb -s "$ANDROID_SERIAL" shell -n pm path "$APP_PACKAGE" 2>/dev/null || true)
if [[ "$INSTALLED_APK" = package:* ]]; then
    adb -s "$ANDROID_SERIAL" shell -n am force-stop "$APP_PACKAGE"
    adb -s "$ANDROID_SERIAL" shell -n pm revoke "$APP_PACKAGE" android.permission.health.READ_EXERCISE
fi
echo 'Testing Recharge on isolated Pro emulator-5582'
./gradlew testDebugUnitTest connectedDebugAndroidTest --no-daemon --max-workers=1 -Dorg.gradle.jvmargs=-Xmx1536m > ../tests-current.log 2>&1
python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

base = Path('app/build')
for folder, minimum in [('test-results/testDebugUnitTest', 4407), ('outputs/androidTest-results/connected/debug', 20)]:
    roots = [ET.parse(path).getroot() for path in base.joinpath(folder).glob('TEST-*.xml')]
    tests = sum(int(root.get('tests', 0)) for root in roots)
    failures = sum(int(root.get('failures', 0)) + int(root.get('errors', 0)) for root in roots)
    skipped = sum(int(root.get('skipped', 0)) for root in roots)
    assert tests - skipped >= minimum, f'{folder}: only {tests - skipped} executed tests, need {minimum}'
    assert failures == 0, f'{folder}: {failures} failures'
    print(f'{folder}: {tests - skipped} executed, {failures} failures')
PY
# Android defers self-revocation while an app remains in the foreground. Exercise
# an external revoke across a real process restart, outside instrumentation.
READ_PERMISSION=android.permission.health.READ_EXERCISE
adb -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/debug/app-debug.apk </dev/null > ../manual-install.log
adb -s "$ANDROID_SERIAL" shell -n am force-stop "$APP_PACKAGE"
adb -s "$ANDROID_SERIAL" shell -n pm grant "$APP_PACKAGE" "$READ_PERMISSION"
adb -s "$ANDROID_SERIAL" shell -n am start -W -n "$APP_PACKAGE/.MainActivity" --ez skipOnboarding true --ez uiTest true >/dev/null
CACHE_READY=false
for attempt in {1..30}; do
    if adb -s "$ANDROID_SERIAL" shell -n run-as "$APP_PACKAGE" test -f files/recovery-cache.json; then CACHE_READY=true; break; fi
    sleep 1
done
test "$CACHE_READY" = true
adb -s "$ANDROID_SERIAL" shell -n am force-stop "$APP_PACKAGE"
adb -s "$ANDROID_SERIAL" shell -n pm revoke "$APP_PACKAGE" "$READ_PERMISSION"
adb -s "$ANDROID_SERIAL" shell -n am start -W -n "$APP_PACKAGE/.MainActivity" --ez skipOnboarding true --ez uiTest true >/dev/null
CACHE_CLEARED=false
for attempt in {1..30}; do
    if adb -s "$ANDROID_SERIAL" shell -n run-as "$APP_PACKAGE" test ! -f files/recovery-cache.json; then CACHE_CLEARED=true; break; fi
    sleep 1
done
test "$CACHE_CLEARED" = true
adb -s "$ANDROID_SERIAL" exec-out screencap -p </dev/null > "$HOME/tmp/sol-recharge/permission-revoked.png"
echo 'Health Connect grant, actual empty read, external revoke and cache removal after restart: PASS'

REMOTE
