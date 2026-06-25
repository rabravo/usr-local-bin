#!/usr/bin/env bash

# ---------------------------------------------------------------
# ab_pdf2png.sh
#
# Converts a PDF file to PNG format using ImageMagick 7.
# Output PNG is saved in the same directory as the input PDF.
# Skips conversion if the output PNG already exists.
#
# Usage:
#   ./ab_pdf2png.sh <input.pdf>
#   ./ab_pdf2png.sh --help
#
# Requirements:
#   ImageMagick 7  — brew install imagemagick
# ---------------------------------------------------------------

set -e

usage() {
    echo "Usage: ./ab_pdf2png.sh <input.pdf>"
    echo "Try:   ./ab_pdf2png.sh --help"
    exit 1
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
ab_pdf2png.sh

Converts a PDF file to PNG format using ImageMagick 7.
The output PNG is saved alongside the input file with the same base name.
Conversion is skipped if the output file already exists.

Usage:
  ./ab_pdf2png.sh <input.pdf>

Options:
  --help, -h    Show this help message

Requirements:
  ImageMagick 7  — brew install imagemagick

Examples:
  ./ab_pdf2png.sh document.pdf
  ./ab_pdf2png.sh /path/to/report.pdf

Output:
  <input_basename>.png  (same directory as input)

EOF
    exit 0
fi

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
