#!/bin/bash
# Mechanical half of the weekly design audit.
#
# Every check here is something that was true of this app before the design
# system existed, and every one of them is invisible in review: a raw 14pt
# padding, a fourth corner radius, a button with no pressed state. The eye
# notices the sum and never the term, so the terms are checked here instead.
#
# What it cannot check is taste. Copy, hierarchy, and whether a screen is worth
# looking at are still the twenty minutes with the app in your hand.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
report() { # name, matches
    local name="$1" hits="$2"
    if [[ -n "$hits" ]]; then
        echo "FAIL  $name"
        echo "$hits" | sed 's/^/      /'
        fail=1
    else
        echo "ok    $name"
    fi
}

VIEWS="Recharge/Views"
ALL="Recharge RechargeWatch RechargeWidget RechargeWatchWidget Shared"

report "every custom button reacts to a press" \
    "$(grep -rn 'buttonStyle(\.plain)' --include='*.swift' $ALL | grep -v ':[0-9]*: *//' || true)"

report "corner radii come from Theme.Radius" \
    "$(grep -rn 'cornerRadius:' --include='*.swift' $ALL | grep -v 'Theme\.Radius' || true)"

report "corners are continuous, never circular" \
    "$(grep -rnE '\.cornerRadius\(|style: \.circular' --include='*.swift' $ALL || true)"

report "spacing sits on the 4pt grid" \
    "$(grep -rnE '\.padding\((\.[a-z]+, )?[0-9]+\)|(spacing|minLength): [0-9]+\b' --include='*.swift' $VIEWS \
        | grep -vE '(: 0\b|, 0\)|\(0\))' || true)"

report "colour is defined once, in Theme" \
    "$(grep -rn 'Color(red:' --include='*.swift' $ALL | grep -v 'Shared/Utilities/Theme.swift' || true)"

report "countdown figures carry tabular digits" \
    "$(grep -rn 'Theme\.bigNumber(' --include='*.swift' $ALL \
        | grep -v 'Shared/Utilities/Theme.swift' || true)"

echo
if [[ $fail -eq 0 ]]; then
    echo "Design system: clean."
else
    echo "Design system: see above. design.md has the rule each check enforces."
fi
exit $fail
