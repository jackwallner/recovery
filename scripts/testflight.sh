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
# Always via scripts/xcgen.sh in this repo (test-plan + scheme patching).
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

echo "==> Upload build $NEXT_BUILD"
"$ROOT/scripts/upload-testflight.sh" "$ARCHIVE"

git add project.yml
git commit -m "chore: bump build $CURRENT_BUILD to $NEXT_BUILD for TestFlight"
echo "==> Build $NEXT_BUILD uploaded"
