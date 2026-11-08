#!/bin/sh
# Compose, gate and publish every locale that has raws. Optional args: store locales.
# usage: tools/build_all.sh [locale ...]   (raws from tools/capture.sh)
set -e
cd "$(dirname "$0")" && . ../.venv/bin/activate
KIT=..; REPO=../../../..
CAT=$REPO/Shared/Localizable.xcstrings
LOCALES=${*:-"cs de-DE es-MX fr-FR it th zh-Hans"}
for l in $LOCALES; do
  [ -d $KIT/raw/$l/phone ] || { echo "skip $l (no raw)"; continue; }
  lang=$(python -c "import json,sys;print(next(t['lang'] for t in json.load(open('$KIT/app.json'))['targets'] if t['store_locale']=='$l'))")
  python reskin.py --config $KIT/frames.json --raw-root $KIT/raw --headers $KIT/copy/headers.json --locale $l --out $KIT/samples
  python sheet.py --config $KIT/frames.json --locale $l --out-root $KIT/samples >/dev/null
  g=$(python gate.py --config $KIT/frames.json --raw-root $KIT/raw --headers $KIT/copy/headers.json --out-root $KIT/samples --locale $l --catalog $CAT --lang $lang 2>&1 | tail -3)
  echo "$l gate: $g"
  case "$g" in *PASS) mkdir -p $REPO/fastlane/screenshots/$l; for p in $KIT/samples/$l/phone/*.png; do cp $p $REPO/fastlane/screenshots/$l/$(basename $p | tr - _); done;; esac
done
