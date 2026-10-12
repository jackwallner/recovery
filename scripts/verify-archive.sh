#!/usr/bin/env bash
# Post-archive checks for Recharge, run by the shared fleet TestFlight script
# between archive and upload (`--post-archive`). Takes the .xcarchive path.
# Needs RC_PUBLIC_KEY in the environment (scripts/testflight.sh exports it).
set -euo pipefail
ARCHIVE="${1:?archive path}"

# The key substitution in testflight.sh is a `sed` on a source file, and a
# `sed` that matches nothing succeeds. Every way that can go wrong (an
# interrupted earlier run that left the key in place and the restore trap then
# reverted it, a rename of the constant, a stale DerivedData object file)
# produces a perfectly valid archive whose paywall cannot configure RevenueCat
# on a real device. Nothing downstream notices: the app builds, launches, and
# simply never loads an offering.
#
# So verify the product rather than trusting the edit. Both the iPhone app and
# the embedded Watch app compile `Shared`, hence the whole-archive search.
echo "==> Verify the production key reached the archive"
if grep -rq "appl_RECHARGE_PLACEHOLDER" "$ARCHIVE/Products"; then
  echo "error: RevenueCat placeholder is in the archive; the key substitution did not take" >&2
  exit 1
fi
if ! grep -rq "${RC_PUBLIC_KEY:?RC_PUBLIC_KEY not set}" "$ARCHIVE/Products"; then
  echo "error: production RevenueCat key not found in the archive" >&2
  exit 1
fi

# Entitlements are applied by the signing step, so anything that stops the
# archive being signed silently strips them: `CODE_SIGN_IDENTITY: ""` in
# `project.yml` did exactly that for builds 21 and 22, and the result was an
# app that installs, launches, and can never read Health. HealthKit's own
# failure is quiet too: `requestAuthorization` throws, no sheet appears, and
# the app never registers under Health > Sharing > Apps, so there is nothing on
# screen that names the cause. Check the product, not the build settings.
echo "==> Verify entitlements survived signing"
APP="$ARCHIVE/Products/Applications/Recharge.app"
APP_ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
if [[ -z "$APP_ENTITLEMENTS" ]]; then
  echo "error: $APP is unsigned, so its entitlements were never applied" >&2
  exit 1
fi
for key in com.apple.developer.healthkit com.apple.security.application-groups; do
  if ! grep -q "$key" <<<"$APP_ENTITLEMENTS"; then
    echo "error: $key is missing from the archived app's entitlements" >&2
    exit 1
  fi
done
for embedded in "$APP/Watch/RechargeWatch.app" \
                "$APP/PlugIns/RechargeWidget.appex" \
                "$APP/Watch/RechargeWatch.app/PlugIns/RechargeWatchWidget.appex"; do
  [[ -e "$embedded" ]] || { echo "error: missing $embedded" >&2; exit 1; }
  if ! codesign -d --entitlements - --xml "$embedded" 2>/dev/null \
       | grep -q "group.com.jackwallner.recovery"; then
    echo "error: App Group missing from $(basename "$embedded")" >&2
    exit 1
  fi
done
echo "==> Archive checks passed"
