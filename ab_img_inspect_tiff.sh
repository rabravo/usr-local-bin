#!/bin/bash
# inspect-tiff.sh
# Bash-only TIFF inspector (no Python)
# Uses: tiffinfo, tiffdump, identify (optional)

if [ -z "$1" ]; then
    echo "Usage: inspect-tiff.sh <file.tif>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "Error: File not found: $FILE"
    exit 1
fi

echo "========================================"
echo "   Inspecting TIFF: $FILE"
echo "========================================"

# ------------------------
# Basic TIFF info
# ------------------------
echo ""
echo "=== TIFF INFO (tiffinfo) ==="
if command -v tiffinfo >/dev/null 2>&1; then
    tiffinfo "$FILE" 2>/dev/null | sed 's/^/  /'
else
    echo "  tiffinfo not installed (install: brew install libtiff)"
fi

# ------------------------
# Page / Directory count
# ------------------------
echo ""
echo "=== PAGE COUNT (tiffdump) ==="
if command -v tiffdump >/dev/null 2>&1; then
    DIRS=$(tiffdump "$FILE" 2>/dev/null | grep "Directory" | wc -l | tr -d ' ')
    echo "  Directories (pages): $DIRS"
else
    echo "  tiffdump not installed (install: brew install libtiff)"
fi

# ------------------------
# Extract width / height / channels
# ------------------------
echo ""
echo "=== BASIC DIMENSIONS ==="

WIDTH=$(tiffinfo "$FILE" 2>/dev/null | grep "Image Width" | head -1 | sed 's/.*Image Width: \([0-9]*\).*/\1/')
HEIGHT=$(tiffinfo "$FILE" 2>/dev/null | grep "Image Length" | head -1 | sed 's/.*Image Length: \([0-9]*\).*/\1/')
SAMPLES=$(tiffinfo "$FILE" 2>/dev/null | grep "Samples/Pixel" | head -1 | sed 's/.*Samples\/Pixel: \([0-9]*\).*/\1/')

echo "  Width:   ${WIDTH:-unknown}"
echo "  Height:  ${HEIGHT:-unknown}"
echo "  Channels: ${SAMPLES:-unknown}"

# ------------------------
# Extract OME XML metadata
# ------------------------
echo ""
echo "=== OME-XML METADATA (if present) ==="

if command -v exiftool >/dev/null 2>&1; then
    XML=$(exiftool -b -OME-XML "$FILE" 2>/dev/null)
    if [ -n "$XML" ]; then
        echo "  Found OME-XML metadata"
        echo "  (showing first 10 lines)"
        echo "$XML" | head -10 | sed 's/^/    /'
    else
        echo "  No OME-XML found"
    fi
else
    echo "  exiftool not installed (brew install exiftool)"
fi

echo ""
echo "Done."
