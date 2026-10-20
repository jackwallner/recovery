#!/usr/bin/env bash
# Connected verification run directly on the emulator host (jmbp or jmbp2),
# against one leased AVD. Usage:
#   ANDROID_SERIAL=emulator-5580 EXPECTED_AVD=agent-emu-1 \
#   REVIEW_CODE_FILE=~/tmp/recharge-review-test/code ./scripts/test-android-host.sh
# The review code file holds a test-only code whose SHA-256 is
# PLAY_REVIEW_CODE_SHA256 in the ignored android/local.properties. The code is
# passed through the environment so it never appears in a recorded command.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_SERIAL:?Set ANDROID_SERIAL to the leased emulator}"
: "${EXPECTED_AVD:?Set EXPECTED_AVD to the leased AVD name}"
: "${REVIEW_CODE_FILE:?Set REVIEW_CODE_FILE to the test reviewer code}"
export JAVA_HOME="${JAVA_HOME:-$HOME/jdks/temurin-17/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
export ANDROID_SERIAL

AVD_NAME=$(adb -s "$ANDROID_SERIAL" emu avd name </dev/null | tr -d '\r' | head -1)
test "$AVD_NAME" = "$EXPECTED_AVD"
test "$(adb -s "$ANDROID_SERIAL" shell -n service check activity)" = 'Service activity: found'

cd "$REPO_DIR/android"
APP_PACKAGE=$(python3 -c 'from pathlib import Path; import re; print(re.search(r"applicationId = \"([^\"]+)\"", Path("app/build.gradle.kts").read_text()).group(1))')
if [[ "$(adb -s "$ANDROID_SERIAL" shell -n pm path "$APP_PACKAGE" 2>/dev/null || true)" = package:* ]]; then
    adb -s "$ANDROID_SERIAL" shell -n am force-stop "$APP_PACKAGE"
    adb -s "$ANDROID_SERIAL" shell -n pm revoke "$APP_PACKAGE" android.permission.health.READ_EXERCISE || true
fi

echo "Testing Recharge on $EXPECTED_AVD ($ANDROID_SERIAL)"
env "ORG_GRADLE_PROJECT_android.testInstrumentationRunnerArguments.reviewCode=$(tr -d '\n' < "$REVIEW_CODE_FILE")" \
    ./gradlew connectedDebugAndroidTest --no-daemon --max-workers=2 -Dorg.gradle.jvmargs=-Xmx2g
python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

base = Path('app/build')
for folder, minimum in [('test-results/testDebugUnitTest', 4411), ('outputs/androidTest-results/connected/debug', 21)]:
    roots = [ET.parse(path).getroot() for path in base.joinpath(folder).glob('TEST-*.xml')]
    tests = sum(int(root.get('tests', 0)) for root in roots)
    failures = sum(int(root.get('failures', 0)) + int(root.get('errors', 0)) for root in roots)
    skipped = sum(int(root.get('skipped', 0)) for root in roots)
    assert tests - skipped >= minimum, f'{folder}: only {tests - skipped} executed tests, need {minimum}'
    assert failures == 0, f'{folder}: {failures} failures'
    print(f'{folder}: {tests - skipped} executed, {failures} failures')
PY

# Android defers self-revocation while an app is in the foreground. Exercise an
# external revoke across a real process restart, outside instrumentation.
READ_PERMISSION=android.permission.health.READ_EXERCISE
adb -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/debug/app-debug.apk </dev/null >/dev/null
adb -s "$ANDROID_SERIAL" shell -n am force-stop "$APP_PACKAGE"
adb -s "$ANDROID_SERIAL" shell -n pm grant "$APP_PACKAGE" "$READ_PERMISSION"
adb -s "$ANDROID_SERIAL" shell -n am start -W -n "$APP_PACKAGE/.MainActivity" --ez skipOnboarding true --ez uiTest true >/dev/null
wait_for_cache() {
    for _ in {1..30}; do
        if adb -s "$ANDROID_SERIAL" shell -n run-as "$APP_PACKAGE" test "$@" files/recovery-cache.json; then return 0; fi
        sleep 1
    done
    return 1
}
wait_for_cache -f
adb -s "$ANDROID_SERIAL" shell -n am force-stop "$APP_PACKAGE"
adb -s "$ANDROID_SERIAL" shell -n pm revoke "$APP_PACKAGE" "$READ_PERMISSION"
adb -s "$ANDROID_SERIAL" shell -n am start -W -n "$APP_PACKAGE/.MainActivity" --ez skipOnboarding true --ez uiTest true >/dev/null
wait_for_cache '!' -f
echo 'Health Connect grant, actual empty read, external revoke and cache removal after restart: PASS'
