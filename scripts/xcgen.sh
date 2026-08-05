#!/usr/bin/env bash
# `xcodegen generate` plus the one thing XcodeGen cannot express.
#
# Use this instead of bare `xcodegen generate` in this repo.
#
# XcodeGen writes `storeKitConfiguration` into the scheme's **Launch** action
# only; there is no key that reaches the **Test** action. `xcodebuild test` runs
# the Test action, so without this patch StoreKit Testing is inactive during
# tests, `Product.products(for:)` returns nothing, and the paywall UI test sees
# the "couldn't load plans" empty state — which is exactly the state that test
# exists to prove we are not looking at.
#
# The failure is loud (the test fails with a message naming this cause), so a
# bare `xcodegen generate` degrades safely rather than silently.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate
python3 scripts/patch-schemes.py
