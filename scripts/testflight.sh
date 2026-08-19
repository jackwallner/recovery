#!/usr/bin/env bash
# Bump, archive, and upload Recharge to TestFlight.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CURRENT_BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
echo "==> Bump build $CURRENT_BUILD -> $NEXT_BUILD"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\")$CURRENT_BUILD/\1$NEXT_BUILD/" project.yml

echo "==> Generate project"
# Always via scripts/xcgen.sh in this repo.
./scripts/xcgen.sh

# The live RevenueCat key never lands in the repo. Substitute it for the archive
# only and restore the placeholder on the way out, however this script exits.
STORE_SERVICE="$ROOT/Shared/Services/StoreService.swift"
CREDS="$HOME/.recovery_credentials"
if [[ ! -f "$CREDS" ]]; then
  echo "error: missing $CREDS (needs RC_PUBLIC_KEY)" >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a; source "$CREDS"; set +a
if [[ -z "${RC_PUBLIC_KEY:-}" ]]; then
  echo "error: RC_PUBLIC_KEY not set in $CREDS" >&2
  exit 1
fi
restore_placeholder() {
  sed -i '' -E "s/appl_[A-Za-z0-9]+/appl_RECHARGE_PLACEHOLDER/" "$STORE_SERVICE"
}
trap restore_placeholder EXIT
echo "==> Substitute production RevenueCat key"
sed -i '' -E "s/appl_RECHARGE_PLACEHOLDER/$RC_PUBLIC_KEY/" "$STORE_SERVICE"

echo "==> Resolve packages"
xcodebuild -resolvePackageDependencies -project Recharge.xcodeproj -scheme Recharge

ARCHIVE="$ROOT/build/Recharge.xcarchive"
rm -rf "$ARCHIVE"

echo "==> Archive Release"
xcodebuild -project Recharge.xcodeproj \
  -scheme Recharge \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

# The substitution above is a `sed` on a source file, and a `sed` that matches
# nothing succeeds. Every way that can go wrong (an interrupted earlier run that
# left the key in place and the restore trap then reverted it, a rename of the
# constant, a stale DerivedData object file) produces a perfectly valid archive
# whose paywall cannot configure RevenueCat on a real device. Nothing downstream
# notices: the app builds, launches, and simply never loads an offering.
#
# So verify the product rather than trusting the edit. Both the iPhone app and
# the embedded Watch app compile `Shared`, hence the whole-archive search.
echo "==> Verify the production key reached the archive"
if grep -rq "appl_RECHARGE_PLACEHOLDER" "$ARCHIVE/Products"; then
  echo "error: RevenueCat placeholder is in the archive; the key substitution did not take" >&2
  exit 1
fi
if ! grep -rq "$RC_PUBLIC_KEY" "$ARCHIVE/Products"; then
  echo "error: production RevenueCat key not found in the archive" >&2
  exit 1
fi

# Entitlements are applied by the signing step, so anything that stops the
# archive being signed silently strips them: `CODE_SIGN_IDENTITY: ""` in
# `project.yml` did exactly that for builds 21 and 22, and the result was an
# app that installs, launches, and can never read Health. HealthKit's own
# failure is quiet too — `requestAuthorization` throws, no sheet appears, and
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

echo "==> Upload build $NEXT_BUILD"
"$ROOT/scripts/upload-testflight.sh" "$ARCHIVE"

git add project.yml
git commit -m "chore: bump build $CURRENT_BUILD to $NEXT_BUILD for TestFlight"
echo "==> Build $NEXT_BUILD uploaded"
