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
WATCH_UDID="${2:-$(agent-sim watch-udid recharge 2>/dev/null || true)}"
BUNDLE="com.jackwallner.recovery"
WATCH_BUNDLE="com.jackwallner.recovery.watch"
RAW="$ROOT/Screenshots/raw"
mkdir -p "$RAW"
find "$RAW" -maxdepth 1 -type f -name '*.png' -delete

# Scene -> output name. Order is the App Store order: the first three frames have
# to be independently understandable because they can appear in search results.
SCENES=(
  "premiumActive:01-countdown"
  "ready:02-ready"
  "history:03-history"
  "paywall:04-pro"
  "settings:05-settings"
)

APP="${RECHARGE_APP_PATH:-}"
if [[ -z "$APP" ]]; then
  APP=$(find ~/Library/Developer/Xcode/DerivedData ~/Library/Developer/XcodeBuildMCP/workspaces \
    -type d -name "Recharge.app" -path "*/Build/Products/*iphonesimulator*" -print0 \
    | xargs -0 ls -td 2>/dev/null | head -1)
fi
[[ -n "$APP" ]] || { echo "error: build Recharge for the simulator first" >&2; exit 1; }

for entry in "${SCENES[@]}"; do
  scene="${entry%%:*}"
  name="${entry##*:}"
  # A clean install prevents SwiftUI scroll restoration from carrying the
  # previous scene's offset into the next App Store frame.
  xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  SIMCTL_CHILD_RECHARGE_SCREENSHOT_MODE=1 \
  SIMCTL_CHILD_RECHARGE_SCREENSHOT_SCENE="$scene" \
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$RAW/$name.png" >/dev/null 2>&1
  echo "captured $name ($scene)"
done

if [[ -n "$WATCH_UDID" ]]; then
  WATCH_APP=$(find "$APP" -name "RechargeWatch.app" -type d | head -1)
  if [[ -n "$WATCH_APP" ]]; then
    xcrun simctl uninstall "$WATCH_UDID" "$WATCH_BUNDLE" 2>/dev/null || true
    xcrun simctl install "$WATCH_UDID" "$WATCH_APP"
    SIMCTL_CHILD_RECHARGE_SCREENSHOT_MODE=1 \
    SIMCTL_CHILD_RECHARGE_SCREENSHOT_SCENE="watchRecovering" \
      xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE" >/dev/null
    sleep 5
    # The watch app launch seeds the deterministic fixture. Return to the
    # active face so this is proof of the WidgetKit complication, not only the
    # full watch app screen.
    command -v axe >/dev/null || {
      echo "error: axe is required to capture the watch face" >&2
      exit 1
    }
    axe button home --udid "$WATCH_UDID" >/dev/null
    sleep 3
    xcrun simctl io "$WATCH_UDID" screenshot "$RAW/06-watch.png" >/dev/null 2>&1
    echo "captured 06-watch (watch face complication)"
  fi
fi

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
python3 "$ROOT/scripts/normalize-screenshots.py"
