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
