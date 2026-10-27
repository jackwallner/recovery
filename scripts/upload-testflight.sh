#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/Recharge.xcarchive}"
STAGING="$ROOT/build/upload-staging"
PLIST="$ROOT/AppStoreUploadOptions.plist"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  echo "Create it with ./scripts/testflight.sh" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "error: missing $PLIST" >&2
  exit 1
fi

# The shared App Store Connect API key, when present, so the upload does not
# depend on an Apple Account signed in to Xcode (lost after a reboot).
AUTH=()
CREDS="${ASC_CREDENTIALS:-$HOME/.baseball_credentials}"
if [[ -f "$CREDS" ]]; then
  set -a; source "$CREDS"; set +a
fi
if [[ -n "${ASC_API_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "${ASC_KEY_PATH:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH"
        -authenticationKeyID "$ASC_API_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "Uploading archive via App Store Connect with the API key..."
else
  echo "Uploading archive via App Store Connect using the local Xcode session..."
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STAGING" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"}
