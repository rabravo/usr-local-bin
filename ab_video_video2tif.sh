#!/usr/bin/env bash
# ab_video_video2tif.sh — extract TIF frames from any video file
#
# Usage:
#   ab_video_video2tif.sh <video> <fps> <duration> [color]
#
# Arguments:
#   video      Path to any video file (mp4, mov, avi, mkv, …)
#   fps        Frames per second to extract
#   duration   Maximum duration to process in seconds (0 = no limit)
#   color      Optional. Pass "color" to keep RGB output; default is grayscale
#
# Output:
#   A directory named after the input file (special characters replaced with _)
#   ending in _tif, containing frame_0001.tif, frame_0002.tif, …
#
# Examples:
#   ab_video_video2tif.sh recording.mp4 14 60
#   ab_video_video2tif.sh recording.mov 10 0 color
#   ab_video_video2tif.sh clip.avi 25 30

set -euo pipefail

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
if ! command -v ffmpeg &>/dev/null; then
  echo "Error: ffmpeg is not installed."
  echo "  brew:  brew install ffmpeg"
  echo "  apt:   sudo apt-get install ffmpeg"
  exit 1
fi

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 3 || "$1" == "--help" || "$1" == "-h" ]]; then
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

video="$1"
fps="$2"
duration="$3"
mode="${4:-gray}"

if [[ ! -f "$video" ]]; then
  echo "Error: file '$video' not found."
  exit 1
fi

if ! [[ "$fps" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$fps <= 0" | bc -l) )); then
  echo "Error: fps must be a positive number (got '$fps')."
  exit 1
fi

if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Error: duration must be a non-negative number in seconds (got '$duration')."
  exit 1
fi

# ---------------------------------------------------------------------------
# OS detection — pick the system temp directory
# ---------------------------------------------------------------------------
case "$(uname -s 2>/dev/null)" in
  Darwin|Linux) _tmpbase="/tmp" ;;
  MINGW*|CYGWIN*|MSYS*) _tmpbase="${TEMP:-${TMP:-/tmp}}" ;;
  *) _tmpbase="/tmp" ;;
esac

# ---------------------------------------------------------------------------
# Output directory (inside system temp)
# ---------------------------------------------------------------------------
raw_stem="$(basename "${video%.*}")"
safe_stem=$(echo "$raw_stem" | sed 's/[^a-zA-Z0-9_-]/_/g')
outdir="${_tmpbase}/${safe_stem}_tif"
mkdir -p "$outdir"
# Remove any frames left from a previous run so stale frames don't outlive the new limit
rm -f "${outdir}"/frame_*.tif

# ---------------------------------------------------------------------------
# Build ffmpeg command
# ---------------------------------------------------------------------------
cmd=(ffmpeg -y -i "$video")

if (( $(echo "$duration > 0" | bc -l) )); then
  cmd+=(-t "$duration")
fi

cmd+=(-vf "fps=${fps}")

if [[ "$mode" == "color" ]]; then
  cmd+=(-pix_fmt rgb24)
else
  cmd+=(-pix_fmt gray)
fi

cmd+=("${outdir}/frame_%04d.tif")

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
echo "Input:    $video"
echo "FPS:      $fps"
echo "Duration: $([ "$(echo "$duration > 0" | bc -l)" -eq 1 ] && echo "${duration}s" || echo "full video")"
echo "Color:    $([ "$mode" == "color" ] && echo "RGB" || echo "grayscale")"
echo "Output:   $outdir/"
echo ""

"${cmd[@]}"

n=$(find "$outdir" -maxdepth 1 -name 'frame_*.tif' | wc -l | tr -d ' ')
echo ""
echo "Done. $n frames saved to ${outdir}/"
