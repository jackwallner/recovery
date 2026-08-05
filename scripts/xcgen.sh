#!/usr/bin/env bash
# `xcodegen generate` for this repo.
#
# This used to also inject the StoreKit configuration into every scheme's Test
# action, on the theory that `xcodebuild test` would then serve the local
# `.storekit` catalogue to the paywall. It does not: with the configuration
# referenced from the Test action, from a test plan (every relative-path
# spelling), and via `SKTestSession` in the UI-test runner, the app under test
# still reaches the live `storekitd` and `Product.products(for:)` comes back
# empty. The paywall UI test now renders `StoreService.screenshotPackages`
# instead — see the doc comment there.
#
# StoreKit Testing still works for the **Launch** action, which XcodeGen writes
# from `storeKitConfiguration:` in project.yml, so running the Recharge scheme
# from Xcode gets the real local catalogue.
#
# Kept as a script so `testflight.sh` and muscle memory keep working.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate
