#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--gray] <input.mp4> [fps]   Convert MP4 to z-stack
  $(basename "$0") --extract <zstack.tif>        Extract all pages from z-stack

Converts an MP4 into a multi-page .tif z-stack where individual frames are
always recoverable. Optionally derives a single-page projection (max/mean/min).
Can also run in reverse to extract all pages from an existing z-stack.

Arguments (convert mode):
  --gray      Output grayscale TIFs (recommended for analysis tools like cardio-tracker)
  input.mp4   Path to the source video file
  fps         Frames per second to sample (optional, prompted if omitted)

Arguments (extract mode):
  --extract   Flag to activate extraction mode
  zstack.tif  Path to a multi-page z-stack .tif file

Prompts in convert mode (before processing begins):
  1. Frames per second to sample
  2. Output option

Output options:
  f) individual frames (no z-stack)
  m) multi-page tif z-stack (default)
  1) z-stack + max projection (brightest pixel across all frames)
  2) z-stack + mean projection (average of all frames)
  3) z-stack + min projection (darkest pixel across all frames)

Output (convert mode):
  A directory named after the input file (special characters replaced with _)
  ending in _tif, containing:
    frame_0001.tif ...        Individual frames (if f selected)
    zstack.tif                Multi-page z-stack (all frames recoverable)
    zstack_<method>.tif       Single-page projection (if 1/2/3 selected)

Output (extract mode):
  Individual frames extracted alongside the z-stack file:
    frame_0001.tif, frame_0002.tif, ...

Examples:
  $(basename "$0") my_video.mp4 10
  $(basename "$0") my_video.mp4             # prompts for fps
  $(basename "$0") --gray my_video.mp4 10   # grayscale output for analysis
  $(basename "$0") --extract my_video_tif/zstack.tif

  Input:  my_video.mp4
  Output: my_video_tif/zstack.tif
          my_video_tif/zstack_mean.tif      # if projection selected
          my_video_tif/frame_0001.tif ...   # if extracted

Prerequisites:
  ffmpeg
    brew:  brew install ffmpeg
    conda: conda install -c conda-forge ffmpeg

  imagemagick
    brew:  brew install imagemagick
    conda: conda install -c conda-forge imagemagick
EOF
}

missing=()
command -v ffmpeg &>/dev/null || missing+=("ffmpeg")
command -v magick &>/dev/null || missing+=("imagemagick")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: the following required tools are not installed:"
  for dep in "${missing[@]}"; do
    echo ""
    echo "  $dep"
    echo "    brew:  brew install $dep"
    echo "    conda: conda install -c conda-forge $dep"
  done
  echo ""
  exit 1
fi

if [[ $# -lt 1 || "$1" == "--help" ]]; then
  usage
  exit 0
fi

gray=0
if [[ "$1" == "--gray" ]]; then
  gray=1
  shift
fi

if [[ "$1" == "--extract" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "Error: --extract requires a path to a zstack .tif file."
    exit 1
  fi
  zstack="$2"
  if [[ ! -f "$zstack" ]]; then
    echo "Error: file '$zstack' not found."
    exit 1
  fi
  outdir="$(dirname "$zstack")"
  echo "Extracting pages from ${zstack}..."
  magick "${zstack}" "${outdir}/frame_%04d.tif"
  echo "Done. Frames saved to ${outdir}/"
  exit 0
fi

input="$1"

if [[ ! -f "$input" ]]; then
  echo "Error: file '$input' not found."
  exit 1
fi

if [[ $# -ge 2 ]]; then
  fps="$2"
else
  read -rp "Frames per second to sample: " fps
fi

echo ""
echo "Output options:"
echo "  f) individual frames (no z-stack)"
echo "  m) multi-page tif z-stack (default)"
echo "  1) z-stack + max projection"
echo "  2) z-stack + mean projection"
echo "  3) z-stack + min projection"
read -rp "Select option [f/m/1/2/3]: " projection
projection="${projection:-m}"

raw_basename="${input%.*}"
basename=$(echo "$raw_basename" | sed 's/[^a-zA-Z0-9_-]/_/g')
outdir="${basename}_tif"
mkdir -p "$outdir"

echo ""
if [[ "$projection" == "f" || "$projection" == "F" ]]; then
  echo "Extracting individual frames..."
  if [[ "$gray" -eq 1 ]]; then
    ffmpeg -i "$input" -vf "fps=${fps}" -pix_fmt gray "${outdir}/frame_%04d.tif"
  else
    ffmpeg -i "$input" -vf "fps=${fps}" "${outdir}/frame_%04d.tif"
  fi
  echo "Done. Output in ${outdir}/"
  exit 0
fi

echo "Building z-stack..."
if [[ "$gray" -eq 1 ]]; then
  ffmpeg -i "$input" -vf "fps=${fps}" -f image2pipe -vcodec ppm - \
    | magick - -colorspace Gray -adjoin "${outdir}/zstack.tif"
else
  ffmpeg -i "$input" -vf "fps=${fps}" -f image2pipe -vcodec ppm - \
    | magick - -adjoin "${outdir}/zstack.tif"
fi
echo "Saved to ${outdir}/zstack.tif"

case "$projection" in
  1)
    echo "Deriving max projection..."
    magick "${outdir}/zstack.tif" -evaluate-sequence max "${outdir}/zstack_max.tif"
    echo "Saved to ${outdir}/zstack_max.tif"
    ;;
  2)
    echo "Deriving mean projection..."
    magick "${outdir}/zstack.tif" -evaluate-sequence mean "${outdir}/zstack_mean.tif"
    echo "Saved to ${outdir}/zstack_mean.tif"
    ;;
  3)
    echo "Deriving min projection..."
    magick "${outdir}/zstack.tif" -evaluate-sequence min "${outdir}/zstack_min.tif"
    echo "Saved to ${outdir}/zstack_min.tif"
    ;;
  m|M)
    echo "Multi-page tif z-stack only."
    ;;
  *)
    echo "Invalid option, defaulting to multi-page tif z-stack."
    ;;
esac

echo ""
echo "Done. Output in ${outdir}/"
