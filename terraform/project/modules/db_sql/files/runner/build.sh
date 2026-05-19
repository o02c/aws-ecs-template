#!/usr/bin/env bash
# Build the Lambda zip contents into build/.
# Called by terraform on every apply via null_resource (lambda.tf).
#
# Layout:
#   src/handler.py         — function code (tracked in git)
#   requirements.txt       — pure-Python deps (tracked)
#   build/                 — pip install target + handler.py (gitignored)
#
# Pure-Python deps only — no compiled wheels, so cross-platform builds work.
set -euo pipefail

command -v pip3 >/dev/null || { echo "ERROR: pip3 not found in PATH"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
BUILD="$HERE/build"

rm -rf "$BUILD"
mkdir -p "$BUILD"

pip3 install --target "$BUILD" -r "$HERE/requirements.txt" --quiet

find "$BUILD" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$BUILD" -name "*.pyc" -delete

cp "$SRC"/*.py "$BUILD/"
