#!/bin/bash

# ---------------------------------------------------------------
# ab_video_avi2mp4.sh
#
# Converts an AVI file to MP4 using ffmpeg.
# Presents an interactive menu to select which variant to produce.
# Output files are saved in the ./media directory.
#
# Encoding settings:
#   -c:v libx264   H.264 video codec
#   -crf 23        Quality level (lower = better; 18-28 is typical)
#   -preset medium Encoding speed/compression trade-off
#   -c:a aac       AAC audio codec
#
# Usage:
#   ./ab_video_avi2mp4.sh <input.avi>
#   ./ab_video_avi2mp4.sh --help
#
# Requirements:
#   ffmpeg  — brew install ffmpeg
#             conda install -c conda-forge ffmpeg
#
# Output:
#   ./media/<filename>.mp4
# ---------------------------------------------------------------

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
ab_video_avi2mp4.sh

Presents an interactive menu to produce MP4 variants from an AVI file
using ffmpeg. Output is written to the ./media directory, which is
created automatically if it does not exist.

Variants available:
  1) Original              — plain AVI to MP4 conversion
  2) No audio              — strips audio track
  3) Trimmed               — clips to a start/end time (prompts for times)
  4) Black & white         — desaturates video
  5) B&W with custom inset — prompts for inset size, corner, and margin
  6) Convert all variants  — runs 1 + 2 + 4 (non-interactive only)

Encoding settings:
  -c:v libx264   H.264 video codec
  -crf 23        Quality level (lower = better; 18-28 is typical)
  -preset medium Encoding speed/compression trade-off
  -c:a aac       AAC audio codec

Usage:
  ./ab_video_avi2mp4.sh <input.avi>

Options:
  --help, -h    Show this help message

Requirements:
  ffmpeg  — brew install ffmpeg
             conda install -c conda-forge ffmpeg

Output:
  ./media/<filename>.mp4

EOF
    exit 0
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: ./ab_video_avi2mp4.sh <input.avi>"
    echo "Try:   ./ab_video_avi2mp4.sh --help"
    exit 1
fi

INPUT="$1"
BASE="${INPUT%.*}"

if [[ ! -f "$INPUT" ]]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

mkdir -p media

# ---------------------------------------------------------------
# Variant functions
# ---------------------------------------------------------------

do_original() {
    local out="media/${BASE}.mp4"
    echo "Converting: $INPUT -> $out"
    ffmpeg -i "$INPUT" -c:v libx264 -crf 23 -preset medium -c:a aac "$out"
}

do_noaudio() {
    local out="media/${BASE}_noaudio.mp4"
    echo "Converting (no audio): $INPUT -> $out"
    ffmpeg -i "$INPUT" -c:v libx264 -crf 23 -preset medium -an "$out"
}

do_trimmed() {
    local out="media/${BASE}_trimmed.mp4"
    read -rp "  Start time (e.g. 00:00:10): " START
    read -rp "  End time   (e.g. 00:01:48): " END
    echo "Converting (trimmed ${START} -> ${END}): $INPUT -> $out"
    ffmpeg -i "$INPUT" -ss "$START" -to "$END" -c:v libx264 -crf 23 -preset medium -c:a aac "$out"
}

do_bw() {
    local out="media/${BASE}_bw.mp4"
    echo "Converting (black & white): $INPUT -> $out"
    ffmpeg -i "$INPUT" -vf "hue=s=0" -c:v libx264 -crf 23 -preset medium -c:a aac "$out"
}

do_inset() {
    echo "  Inset size (fraction of video width):"
    echo "    1) 1/4"
    echo "    2) 1/3"
    echo "    3) 1/2"
    read -rp "  Select [1-3, default 1]: " SIZE_CHOICE
    local frac
    case "$SIZE_CHOICE" in
        2) frac=3 ;;
        3) frac=2 ;;
        *) frac=4 ;;
    esac

    echo "  Inset corner:"
    echo "    1) Bottom-right"
    echo "    2) Bottom-left"
    echo "    3) Top-right"
    echo "    4) Top-left"
    read -rp "  Select [1-4, default 1]: " POS_CHOICE
    read -rp "  Margin from edge in pixels [default 10]: " MARGIN
    MARGIN="${MARGIN:-10}"

    local overlay
    case "$POS_CHOICE" in
        2) overlay="${MARGIN}:H-h-${MARGIN}" ;;
        3) overlay="W-w-${MARGIN}:${MARGIN}" ;;
        4) overlay="${MARGIN}:${MARGIN}" ;;
        *) overlay="W-w-${MARGIN}:H-h-${MARGIN}" ;;
    esac

    local out="media/${BASE}_bw_inset_custom.mp4"
    echo "Converting (B&W + custom inset): $INPUT -> $out"
    ffmpeg -i "$INPUT" \
        -filter_complex "[0:v]hue=s=0[bw];[0:v]scale=iw/${frac}:-2[inset];[bw][inset]overlay=${overlay}" \
        -c:v libx264 -crf 23 -preset medium -c:a aac "$out"
}

# ---------------------------------------------------------------
# Menu
# ---------------------------------------------------------------
echo ""
echo "Select a variant to produce from: $INPUT"
echo ""
select CHOICE in \
    "Original              (${BASE}.mp4)" \
    "No audio              (${BASE}_noaudio.mp4)" \
    "Trimmed               (${BASE}_trimmed.mp4)" \
    "Black & white         (${BASE}_bw.mp4)" \
    "B&W with custom inset (${BASE}_bw_inset_custom.mp4)" \
    "Convert all variants  (1 + 2 + 4)" \
    "Quit"
do
    case "$REPLY" in
        1) do_original ;;
        2) do_noaudio ;;
        3) do_trimmed ;;
        4) do_bw ;;
        5) do_inset ;;
        6)
            do_original
            do_noaudio
            do_bw
            ;;
        7) echo "Exiting."; exit 0 ;;
        *) echo "Invalid option. Please select 1-7." ;;
    esac
    break
done
