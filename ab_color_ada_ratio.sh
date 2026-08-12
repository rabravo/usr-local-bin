#!/usr/bin/env bash
# Compute the WCAG 2.1 contrast ratio between two RGB hex colors and report
# whether they meet the AA accessibility minimum.
#
# Formula (W3C WCAG 2.1 §1.4.3):
#   1. Normalize each channel:  C_sRGB = C_8bit / 255
#   2. Linearize:               C <= 0.04045  →  C / 12.92
#                               C >  0.04045  →  ((C + 0.055) / 1.055) ^ 2.4
#   3. Relative luminance:      L = 0.2126·R + 0.7152·G + 0.0722·B
#   4. Contrast ratio:          (L_lighter + 0.05) / (L_darker + 0.05)
#
# AA thresholds:
#   Normal text  ≥ 4.5 : 1
#   Large text   ≥ 3.0 : 1  (18 pt+ or 14 pt+ bold)
#
# Usage:
#   ab_color_ada_ratio.sh <hex1> <hex2>

set -euo pipefail

show_help() {
cat << EOF
Usage: $(basename "$0") <hex1> <hex2>

Compute the WCAG 2.1 contrast ratio between two hex colors and check AA compliance.
Hex values may include or omit the leading '#'.

Examples:
  $(basename "$0") "#ffffff" "#000000"
  $(basename "$0") ffffff 595959

Options:
  -h, --help   Show this help message and exit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ $# -lt 2 ]]; then
  echo "Error: two hex color values are required."
  show_help
  exit 1
fi

hex1="${1#\#}"
hex2="${2#\#}"

for hex in "$hex1" "$hex2"; do
  if [[ ! "$hex" =~ ^[0-9a-fA-F]{6}$ ]]; then
    echo "Error: '$hex' is not a valid 6-digit hex color."
    exit 1
  fi
done

# Convert hex pairs to decimal channel values (0-255)
r1=$(printf '%d' "0x${hex1:0:2}")
g1=$(printf '%d' "0x${hex1:2:2}")
b1=$(printf '%d' "0x${hex1:4:2}")

r2=$(printf '%d' "0x${hex2:0:2}")
g2=$(printf '%d' "0x${hex2:2:2}")
b2=$(printf '%d' "0x${hex2:4:2}")

awk -v r1="$r1" -v g1="$g1" -v b1="$b1" \
    -v r2="$r2" -v g2="$g2" -v b2="$b2" \
    -v hex1="${hex1^^}" -v hex2="${hex2^^}" '
function linearize(c,    s) {
    s = c / 255.0
    if (s <= 0.04045)
        return s / 12.92
    return ((s + 0.055) / 1.055) ^ 2.4
}
function luminance(r, g, b) {
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
}
BEGIN {
    L1 = luminance(r1, g1, b1)
    L2 = luminance(r2, g2, b2)

    lighter = (L1 > L2) ? L1 : L2
    darker  = (L1 < L2) ? L1 : L2

    ratio = (lighter + 0.05) / (darker + 0.05)

    printf "\n  Color 1 : #%s  (L = %.6f)\n", hex1, L1
    printf "  Color 2 : #%s  (L = %.6f)\n", hex2, L2
    printf "\n  Contrast ratio : %.2f:1\n\n", ratio

    printf "  WCAG 2.1 AA — Normal text (>= 4.5:1) : %s\n", (ratio >= 4.5 ? "PASS" : "FAIL")
    printf "  WCAG 2.1 AA — Large text  (>= 3.0:1) : %s\n\n", (ratio >= 3.0 ? "PASS" : "FAIL")
}
'
