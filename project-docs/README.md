# Project documentation

Developer notes and historical audits for this repository. The published site remains in the docs directory.

## Audits

- [ios27Recharge.md](audits/ios27Recharge.md): iOS 27 compatibility audit: Recharge
- [lsa817.md](audits/lsa817.md): Recharge target-user release audit
- [state-machines-2026-11-06.md](audits/state-machines-2026-11-06.md): state machine audit: Recharge (4 bugs, 2 proved by test; repro suite beside it)
- [state-machines-2026-11-06-review.md](audits/state-machines-2026-11-06-review.md): independent review of that audit (2 confirmed, 2 confirmed-minor, 0 false positives; B2 ranked first)
- [state-machines-2026-11-06-fixes.md](audits/state-machines-2026-11-06-fixes.md): fixes for the confirmed claims (5 fixed, 0 held, 0 skipped; regression tests in `StateMachineRegressionTests`)

## Design

- [design.md](design/design.md): Recharge design system

## Android

- [Android](android/README.md): native port verification evidence.
