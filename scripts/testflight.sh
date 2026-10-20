#!/usr/bin/env bash
# Bump, archive, and upload Recharge to TestFlight.
#
# The audit, tests and RevenueCat key substitution are this app's own. The bump,
# archive, upload and bump commit are the shared fleet script
# (~/ios/release/testflight.sh), which also runs scripts/verify-archive.sh on
# the archive before anything is uploaded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The design system's mechanical half, before anything is bumped. Every check
# it runs was a real regression in this app once, and all of them are invisible
# in a diff: an off-grid padding, a fourth corner radius, a button that does not
# react to a press. See project-docs/design/design.md.
echo "==> Design audit"
./scripts/design-audit.sh

echo "==> Unit tests"
TEST_UDID="${RECHARGE_TEST_UDID:-$(agent-sim udid recharge)}"
xcodebuild test \
  -project Recharge.xcodeproj \
  -scheme Recharge \
  -only-testing:RechargeTests \
  -destination "id=$TEST_UDID" \
  -derivedDataPath "/tmp/recharge-testflight-tests" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO

echo "==> Signed UI and HealthKit walkthrough"
xcodebuild test \
  -project Recharge.xcodeproj \
  -scheme RechargeUITests \
  -destination "id=$TEST_UDID" \
  -derivedDataPath "/tmp/recharge-testflight-ui" \
  -quiet \
  -parallel-testing-enabled NO

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

# Not exec: the trap above must restore the placeholder after the upload.
"$HOME/ios/release/testflight.sh" --project Recharge.xcodeproj --scheme Recharge \
  --post-archive "$ROOT/scripts/verify-archive.sh" "$@"
