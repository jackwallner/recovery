#!/usr/bin/env bash
# Capture the App Store screenshot set from a leased pool simulator.
#
# Must run on the default checkout (iPhone 17 Pro) so the raw geometry is
# deterministic: 1206x2622. `normalize-screenshots.py` then produces the
# 1320x2868 APP_IPHONE_67 assets ASC expects, keeping the raw capture beside it
# for design review.
#
#   agent-sim checkout recharge
#   ./scripts/capture-screenshots.sh "$(agent-sim udid recharge)"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:-$(agent-sim udid recharge)}"
BUNDLE="com.jackwallner.recharge"
RAW="$ROOT/Screenshots/raw"
mkdir -p "$RAW"

# Scene -> output name. Order is the App Store order: the first three frames have
# to be independently understandable because they can appear in search results.
SCENES=(
  "recovering:01-countdown"
  "ready:02-ready"
  "history:03-history"
  "premiumActive:04-pro"
  "settings:05-settings"
)

APP=$(find ~/Library/Developer/Xcode/DerivedData/Recharge-*/Build/Products \
  -maxdepth 2 -name "Recharge.app" -path "*iphonesimulator*" | head -1)
[[ -n "$APP" ]] || { echo "error: build Recharge for the simulator first" >&2; exit 1; }

xcrun simctl install "$UDID" "$APP"

for entry in "${SCENES[@]}"; do
  scene="${entry%%:*}"
  name="${entry##*:}"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_RECHARGE_SCREENSHOT_MODE=1 \
  SIMCTL_CHILD_RECHARGE_SCREENSHOT_SCENE="$scene" \
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$RAW/$name.png" >/dev/null 2>&1
  echo "captured $name ($scene)"
done

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
python3 "$ROOT/scripts/normalize-screenshots.py"
