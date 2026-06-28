#!/usr/bin/env bash
# ab_video_yt_transcript.sh
# Download a YouTube transcript, audio (MP3), or both.
#
# Usage:
#   bash ab_video_yt_transcript.sh "https://www.youtube.com/watch?v=VIDEO_ID"
#   bash ab_video_yt_transcript.sh "https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID&start_radio=1"
#
# NOTE: Always quote the URL — unquoted & characters are shell metacharacters
#       that will background the script and break interactive input.
#
# Dependencies:
#   curl     — pre-installed on macOS and most Linux distros
#   xmllint  — macOS: pre-installed | Debian/Ubuntu: apt install libxml2-utils | RHEL/Fedora: dnf install libxml2
#              (optional for transcript: falls back to grep-based parsing if not found)
#   yt-dlp   — required for audio download only: pip install yt-dlp  OR  brew install yt-dlp
#
# How transcript fetch works:
#   1. Fetch the video page to extract the INNERTUBE_API_KEY
#   2. POST to YouTube's innertube/v1/player API using the iOS client context
#      (iOS client returns timedtext URLs accessible without browser cookies;
#      page-embedded URLs return empty bodies without browser auth)
#   3. Extract the English caption track URL from the JSON response
#   4. Fetch and parse the transcript XML with xmllint

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") <YouTube_URL>"
    echo
    echo "  Example: $(basename "$0") \"https://www.youtube.com/watch?v=VIDEO_ID\""
    echo "  Example: $(basename "$0") \"https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID&start_radio=1\""
    echo
    echo "  NOTE: Always quote the URL — unquoted & characters background the script"
    echo "        and break interactive input."
    echo
    echo "Dependencies:"
    echo "  curl     — pre-installed on macOS and most Linux distros"
    echo "  xmllint  — macOS: pre-installed | Debian/Ubuntu: apt install libxml2-utils | RHEL/Fedora: dnf install libxml2"
    echo "             (optional for transcript: falls back to grep-based parsing if not found)"
    echo "  yt-dlp   — required for audio: pip install yt-dlp  OR  brew install yt-dlp"
    exit 1
}

die() { echo "❌ $*" >&2; exit 1; }

[[ $# -lt 1 ]] && usage

URL="$1"

# ---------- 1. Extract video ID ----------
if [[ "$URL" == *"v="* ]]; then
    VIDEO_ID=$(echo "$URL" | sed 's/.*[?&]v=\([^&]*\).*/\1/')
elif [[ "$URL" == *"youtu.be/"* ]]; then
    VIDEO_ID=$(echo "$URL" | sed 's|.*youtu\.be/\([^?]*\).*|\1|')
else
    die "Invalid YouTube URL format."
fi

echo "Video ID: $VIDEO_ID"
echo

# ---------- 2. Menu ----------
echo "What would you like to download?"
echo "  1) Transcript only"
echo "  2) Audio (MP3) only"
echo "  3) Both"
echo
read -rp "Choice [1-3]: " CHOICE

case "$CHOICE" in
    1) DO_TRANSCRIPT=true;  DO_AUDIO=false ;;
    2) DO_TRANSCRIPT=false; DO_AUDIO=true  ;;
    3) DO_TRANSCRIPT=true;  DO_AUDIO=true  ;;
    *) die "Invalid choice — please enter 1, 2, or 3." ;;
esac

echo

# ---------- 3. Dependency checks ----------
if [[ "$DO_AUDIO" == true ]] && ! command -v yt-dlp &>/dev/null; then
    die "yt-dlp not found — required for audio download.\n  Install: pip install yt-dlp  OR  brew install yt-dlp"
fi

if [[ "$DO_TRANSCRIPT" == true ]] && ! command -v xmllint &>/dev/null; then
    echo "⚠️  xmllint not found — using grep fallback (install libxml2-utils for best results)"
fi

# ---------- 4. Transcript ----------
TRANSCRIPT_FAILED=false
if [[ "$DO_TRANSCRIPT" == true ]]; then
  (
    echo "Fetching transcript..."

    PAGE=$(curl -s --max-time 15 \
        -H "Accept-Language: en-US,en;q=0.9" \
        -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        "https://www.youtube.com/watch?v=${VIDEO_ID}") \
        || die "Failed to fetch video page."

    [[ -z "$PAGE" ]] && die "Empty response from YouTube."

    API_KEY=$(echo "$PAGE" | \
        grep -oE '"INNERTUBE_API_KEY":"[^"]*"' | \
        head -1 | \
        sed 's/"INNERTUBE_API_KEY":"//;s/"$//' || true)

    # Fall back to well-known public key if page didn't yield one
    [[ -z "$API_KEY" ]] && API_KEY="AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"

    # iOS client context returns signed timedtext URLs accessible without browser cookies.
    # --data-raw prevents curl from misinterpreting video IDs that start with '-'.
    INNERTUBE_RESP=$(curl -s --max-time 15 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Accept-Language: en-US,en;q=0.9" \
        "https://www.youtube.com/youtubei/v1/player?key=${API_KEY}" \
        --data-raw "{\"context\":{\"client\":{\"clientName\":\"IOS\",\"clientVersion\":\"20.10.38\"}},\"videoId\":\"${VIDEO_ID}\"}") \
        || die "Failed to call innertube API."

    [[ -z "$INNERTUBE_RESP" ]] && die "Empty innertube API response."

    if echo "$INNERTUBE_RESP" | grep -q '"status":"ERROR"'; then
        die "Video not found or unavailable."
    fi

    # Prefer English; fall back to first available track
    CAPTION_URL=$(echo "$INNERTUBE_RESP" | \
        grep -oE '"baseUrl": ?"https://www\.youtube\.com/api/timedtext[^"]*lang=en[^"]*"' | \
        head -1 | \
        sed 's|"baseUrl": *"||;s/"$//' || true)

    if [[ -z "$CAPTION_URL" ]]; then
        CAPTION_URL=$(echo "$INNERTUBE_RESP" | \
            grep -oE '"baseUrl": ?"https://www\.youtube\.com/api/timedtext[^"]*"' | \
            head -1 | \
            sed 's|"baseUrl": *"||;s/"$//' || true)
    fi

    [[ -z "$CAPTION_URL" ]] && die "No transcript/captions found for this video."

    TRANSCRIPT_XML=$(curl -s "$CAPTION_URL") || die "Failed to fetch transcript."
    [[ -z "$TRANSCRIPT_XML" ]] && die "Empty transcript response."

    decode_entities() {
        # Decode &amp; first so double-encoded sequences like &amp;#39; resolve in one pass
        sed "s/&amp;/\&/g;s/&#39;/'/g;s/&quot;/\"/g;s/&lt;/</g;s/&gt;/>/g"
    }

    if command -v xmllint &>/dev/null; then
        FULL_TEXT=$(echo "$TRANSCRIPT_XML" | \
            xmllint --xpath '//text/text()' - 2>/dev/null | \
            decode_entities | \
            tr '\n' ' ' | \
            sed 's/  */ /g;s/^ //;s/ $//')
    else
        FULL_TEXT=$(echo "$TRANSCRIPT_XML" | \
            grep -oE '>[^<]+</text>' | \
            sed 's/^>//;s/<\/text>$//' | \
            decode_entities | \
            tr '\n' ' ' | \
            sed 's/  */ /g;s/^ //;s/ $//')
    fi

    [[ -z "$FULL_TEXT" ]] && die "Could not parse transcript content."

    TEXT_LEN=${#FULL_TEXT}
    if [[ $TEXT_LEN -gt 2000 ]]; then
        echo "${FULL_TEXT:0:2000}…"
    else
        echo "$FULL_TEXT"
    fi
    echo

    TRANSCRIPT_FILE="${VIDEO_ID}_transcript.txt"
    printf '%s\n' "$FULL_TEXT" > "$TRANSCRIPT_FILE"
    echo "✅ Transcript saved to: $TRANSCRIPT_FILE"
  ) || TRANSCRIPT_FAILED=true
fi

# ---------- 5. Audio ----------
AUDIO_FAILED=false
if [[ "$DO_AUDIO" == true ]]; then
  (
    echo "Downloading audio (MP3)..."
    yt-dlp \
        --extract-audio \
        --audio-format mp3 \
        --audio-quality 0 \
        -o "${VIDEO_ID}.%(ext)s" \
        "https://www.youtube.com/watch?v=${VIDEO_ID}" \
        || die "yt-dlp failed to download audio."
    echo "✅ Audio saved to: ${VIDEO_ID}.mp3"
  ) || AUDIO_FAILED=true
fi

# ---------- 6. Partial-failure guidance (option 3 only) ----------
if [[ "$CHOICE" == "3" ]]; then
    if [[ "$TRANSCRIPT_FAILED" == true && "$AUDIO_FAILED" == false ]]; then
        echo
        echo "⚠️  Transcript failed — audio was saved successfully."
        echo "   To retry the transcript, re-run the script and choose option 1."
        exit 1
    elif [[ "$AUDIO_FAILED" == true && "$TRANSCRIPT_FAILED" == false ]]; then
        echo
        echo "⚠️  Audio failed — transcript was saved successfully."
        echo "   To retry the audio, re-run the script and choose option 2."
        exit 1
    elif [[ "$TRANSCRIPT_FAILED" == true && "$AUDIO_FAILED" == true ]]; then
        echo
        echo "❌ Both transcript and audio failed. Check the errors above and retry."
        exit 1
    fi
fi
