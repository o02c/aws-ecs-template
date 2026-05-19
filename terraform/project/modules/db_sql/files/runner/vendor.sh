#!/usr/bin/env bash
# Re-vendor pg8000 and its pure-Python deps into src/.
# Run this when bumping requirements.txt.
#
# IMPORTANT: *.dist-info directories MUST be retained — scramp uses
# importlib.metadata.version() at import time and AWS Lambda will fail with
# "No package metadata was found for scramp" if they are stripped.
set -euo pipefail
shopt -s nullglob

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pip3 install --target "$TMP" -r "$HERE/requirements.txt" --quiet

# Clean existing vendored content (keep handler.py and other source files).
rm -rf \
    "$SRC"/pg8000 "$SRC"/scramp "$SRC"/asn1crypto "$SRC"/dateutil "$SRC"/six.py \
    "$SRC"/*.dist-info

cp -R \
    "$TMP"/pg8000 "$TMP"/scramp "$TMP"/asn1crypto "$TMP"/dateutil "$TMP"/six.py \
    "$SRC/"
for d in "$TMP"/*.dist-info; do
    cp -R "$d" "$SRC/"
done

find "$SRC" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$SRC" -name "*.pyc" -delete

echo "Vendored to $SRC ($(du -sh "$SRC" | cut -f1))"
