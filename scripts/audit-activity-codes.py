#!/usr/bin/env python3
"""Compare the app's pinned HKWorkoutActivityType raw values against the SDK."""

import re
import subprocess
import sys

SDK = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
HEADER = f"{SDK}/System/Library/Frameworks/HealthKit.framework/Headers/HKWorkout.h"

# ── Truth: parse the enum, honouring implicit increments ────────────────────
source = open(HEADER).read()
block = re.search(
    r"typedef NS_ENUM\(NSUInteger, HKWorkoutActivityType\)\s*\{(.*?)\n\}",
    source, re.S,
).group(1)

truth = {}
nxt = 0
for line in block.splitlines():
    line = line.split("//")[0].strip()
    m = re.match(r"HKWorkoutActivityType([A-Za-z]+)\b(.*)", line)
    if not m:
        continue
    name, rest = m.group(1), m.group(2)
    explicit = re.search(r"=\s*(\d+)", rest)
    value = int(explicit.group(1)) if explicit else nxt
    truth[name[0].lower() + name[1:]] = value
    nxt = value + 1

# ── The app's pinned table ─────────────────────────────────────────────────
app_source = open("/Users/jackwallner/recovery/Shared/Utilities/WorkoutClassifier.swift").read()
enum_block = re.search(r"enum ActivityCode: UInt, Sendable \{(.*?)\n    \}", app_source, re.S).group(1)
app = {}
for m in re.finditer(r"case (\w+) = (\d+)", enum_block):
    app[m.group(1)] = int(m.group(2))

# ── The app's profile mapping, so we can say what the mistake COSTS ─────────
profile_block = re.search(r"switch code \{(.*?)\n        \}", app_source, re.S).group(1)
profile_of = {}
pending = []
for line in profile_block.splitlines():
    stripped = line.strip()
    if stripped.startswith("//"):
        continue
    if stripped.startswith("case ") or stripped.startswith("."):
        pending += re.findall(r"\.(\w+)", stripped)
    if "return ." in stripped:
        target = re.search(r"return \.(\w+)", stripped).group(1)
        for name in pending:
            profile_of[name] = target
        pending = []

app_by_value = {v: k for k, v in app.items()}


def app_profile_for(raw):
    """What the app actually does with this raw value today."""
    if raw in (20, 63):  # the ambiguous codes
        return "mixed (user setting)"
    name = app_by_value.get(raw)
    if name is None:
        return "endurance (unknown code fallback)"
    return profile_of.get(name, "endurance (default branch)")


print(f"SDK: {SDK.split('/')[-1]}")
print(f"SDK defines {len(truth)} activity types; the app pins {len(app)}.\n")

print("═" * 104)
print("MISMATCHES — the app's raw value does not name the activity it thinks it does")
print("═" * 104)
print(f"{'app case':32}{'app value':11}{'真 SDK value':14}{'what that value REALLY is':28}")
print("─" * 104)
bad = 0
for name, value in sorted(app.items(), key=lambda kv: kv[1]):
    real = truth.get(name)
    if real is None:
        print(f"{name:32}{value:<11}{'—':14}{'not in SDK at all':28}")
        bad += 1
    elif real != value:
        occupant = next((n for n, v in truth.items() if v == value), "unassigned")
        print(f"{name:32}{value:<11}{real:<14}{occupant:28}")
        bad += 1
print("─" * 104)
print(f"{bad} mismatched\n")

print("═" * 104)
print("CONSEQUENCES — for each real SDK activity, what profile the app assigns today")
print("═" * 104)
print(f"{'real activity':34}{'raw':6}{'app reads it as':30}{'profile it gets':26}")
print("─" * 104)
suspicious = []
for name, raw in sorted(truth.items(), key=lambda kv: kv[1]):
    if raw >= 3000:
        continue
    reads_as = app_by_value.get(raw, "—")
    prof = app_profile_for(raw)
    flag = ""
    if reads_as != name and reads_as != "—":
        flag = "  ← WRONG NAME"
        suspicious.append((name, raw, reads_as, prof))
    elif reads_as == "—":
        flag = "  ← unmapped"
        suspicious.append((name, raw, "unmapped", prof))
    print(f"{name:34}{raw:<6}{reads_as:30}{prof:26}{flag}")

print("\n" + "═" * 104)
print(f"{len(suspicious)} activities are either misnamed or unmapped")
print("═" * 104)
for name, raw, reads_as, prof in suspicious:
    print(f"  {raw:>4}  {name:<32} read as {reads_as:<28} -> {prof}")
