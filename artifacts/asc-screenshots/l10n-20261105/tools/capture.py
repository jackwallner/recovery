#!/usr/bin/env python3
"""Capture every locale/scene in ONE gh-sim launch job, then sort into raw/.

usage: capture.py [--sort RESULT_DIR] [locale ...]   (no args: submit + sort all)
Scenes map to the 01..05 frames: recovering, ready, history, settings.
"""
import json, os, shutil, subprocess, sys
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
REPO = KIT.parent.parent.parent
SCENES = [("recovering", "01-countdown"), ("ready", "02-ready"),
          ("history", "03-history"), ("settings", "05-settings")]
DEVICE = "iPhone 17 Pro Max"


def targets(only):
    app = json.load(open(KIT / "app.json"))
    t = [(x["store_locale"], x["apple_languages"], x["apple_locale"]) for x in app["targets"]]
    if only:
        t = [x for x in t if x[0] in only]
    return t if only else [("en-US", "(en)", "en_US")] + t


def plan(only):
    out = []
    for loc, langs, aloc in targets(only):
        for scene, name in SCENES:
            out.append((loc, name, f"-AppleLanguages {langs} -AppleLocale {aloc} "
                        f"-RECHARGE_SCREENSHOT_MODE 1 -RECHARGE_SCREENSHOT_SCENE {scene}"))
    return out


def sort(result, only):
    p = plan(only)
    shots = Path(result) / "shots"
    for i, (loc, name, _) in enumerate(p, 1):
        src = next(shots.glob(f"screen{i}-*.png"), None)
        if not src:
            print("missing", loc, name); continue
        dst = KIT / "raw" / loc / "phone" / f"{name}.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(src, dst)
    print("sorted", len(p))


def main():
    a = sys.argv[1:]
    if a[:1] == ["--sort"]:
        return sort(a[1], a[2:])
    p = plan(a)
    idf = KIT / ".gh-sim-id"
    cmd = ["gh-sim", "-C", str(REPO), "launch", "--device", DEVICE, "--wait", "8",
           "--id-file", str(idf)]
    for _, _, args in p:
        cmd += ["--screen", args]
    r = subprocess.run(cmd)
    if not idf.exists():
        sys.exit(f"gh-sim exited {r.returncode} before starting a run")
    rid = idf.read_text().strip()
    res = Path.home() / ".gh-sim/results" / rid
    print("result", res, "exit", r.returncode)
    sort(res, a)


main()
