#!/usr/bin/env python3
"""Inject the StoreKit configuration into each scheme's TestAction.

See `scripts/xcgen.sh` for why this is needed. Idempotent: running it twice does
nothing the second time.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMES_DIR = os.path.join(ROOT, "Recharge.xcodeproj", "xcshareddata", "xcschemes")

REFERENCE = """      <StoreKitConfigurationFileReference
         identifier = "../../Recharge.storekit">
      </StoreKitConfigurationFileReference>
"""


def patch(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    match = re.search(r"<TestAction\b.*?</TestAction>", text, re.DOTALL)
    if not match:
        return False

    action = match.group(0)
    if "StoreKitConfigurationFileReference" in action:
        return False

    patched = action.replace("   </TestAction>", REFERENCE + "   </TestAction>")
    if patched == action:
        print(f"warning: could not find the TestAction close tag in {path}", file=sys.stderr)
        return False

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text[: match.start()] + patched + text[match.end():])
    return True


def main():
    if not os.path.isdir(SCHEMES_DIR):
        print(f"error: no schemes at {SCHEMES_DIR}; run xcodegen first", file=sys.stderr)
        return 1

    for name in sorted(os.listdir(SCHEMES_DIR)):
        if not name.endswith(".xcscheme"):
            continue
        path = os.path.join(SCHEMES_DIR, name)
        if patch(path):
            print(f"patched TestAction StoreKit config into {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
