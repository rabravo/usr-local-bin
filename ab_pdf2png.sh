#!/usr/bin/env bash
set -e

usage() {
  echo "Usage: $0 <input.pdf>"
  exit 1
}

[ $# -eq 1 ] || usage

pdfFile="$1"

[ -f "$pdfFile" ] || { echo "File not found: $pdfFile"; exit 1; }

if ! command -v magick >/dev/null 2>&1; then
  echo "Error: 'magick' not found. Install ImageMagick 7."
  exit 1
fi

pngFile="${pdfFile%.*}.png"

if [ ! -f "$pngFile" ]; then
  echo "Converting..."
  magick -density 300 "$pdfFile" "$pngFile"
else
  echo "Output exists. Skipping."
fi
