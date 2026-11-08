#!/bin/sh
# Reruns every capture (one gh-sim job). Optional args: store locales.
cd "$(dirname "$0")/.." && . .venv/bin/activate && exec python tools/capture.py "$@"
