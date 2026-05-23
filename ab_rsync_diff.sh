#!/usr/bin/env bash
# ab_rsync_diff.sh — Color-coded diff using rsync dry-run as file filter + stat for details
#
# USAGE
#   ./ab_rsync_diff.sh -l PATH -r PATH -u USER -s HOST [--checksum]
#
# NOTE
#   Uses rsync --dry-run to detect changed files efficiently, then fetches
#   timestamps and permissions via a single SSH stat pass. Because rsync
#   compares local→remote only, files that are newer on the remote side are
#   NOT detected and will not appear in the output. For bidirectional
#   timestamp comparison use ab_sync_diff.sh instead.
#
#   All four flags are required. Running with no arguments prints this help.
#
# REQUIRED FLAGS
#   -l, --local  PATH   Local directory to compare
#   -r, --remote PATH   Absolute path of the remote directory
#   -u, --user   USER   SSH username on the remote server
#   -s, --server HOST   Remote hostname or IP address
#
# OPTIONAL FLAGS
#   -c, --checksum      Compare files by content checksum instead of timestamp/size.
#                       Slower but catches files that differ in content while sharing
#                       the same modification time (e.g. copied with scp -p).
#   -h, --help          Show this help message and exit
#
# OUTPUT COLUMNS
#   FILE          Relative file path (truncated with ... if wider than column)
#   LOCAL PERMS   Permission bits of the local file  (e.g. -rw-r--r--)
#   LOCAL DATE    Last-modified timestamp of the local file
#   REMOTE PERMS  Permission bits of the remote file
#   REMOTE DATE   Last-modified timestamp of the remote file
#   STATUS        One of: LOCAL NEWER, LOCAL ONLY, REMOTE ONLY
#
# COLOR CODING
#   Green   File exists on both sides and local is newer or differs
#   Yellow  File exists on only one side (local only or remote only)
#
# EXAMPLES
#   ./ab_rsync_diff.sh -l ~/myproject -r /remote/myproject -u alice -s hpc.university.edu
#       Show all files that differ between local and remote
#
#   ./ab_rsync_diff.sh -l ~/myproject -r /remote/myproject -u alice -s hpc.university.edu --checksum
#       Use checksum comparison instead of timestamp (slower, catches scp -p copies)
#
#   ./ab_rsync_diff.sh -l ~/myproject -r /remote/myproject -u alice -s hpc.university.edu | less -R
#       Scroll through a long output while preserving colors
#

# ── Argument parsing ──────────────────────────────────────────
LOCAL_DIR=""
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_DIR=""
CHECKSUM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--local)    LOCAL_DIR="$2";   shift 2 ;;
        -r|--remote)   REMOTE_DIR="$2";  shift 2 ;;
        -u|--user)     REMOTE_USER="$2"; shift 2 ;;
        -s|--server)   REMOTE_HOST="$2"; shift 2 ;;
        -c|--checksum) CHECKSUM=true;    shift ;;
        -h|--help)
            awk 'f && !/^#/{exit} /^# USAGE/{f=1} f{sub(/^# ?/,""); print}' "$0"
            exit 0 ;;
        *)
            printf "Unknown option: %s\nRun with -h for help.\n" "$1" >&2
            exit 1 ;;
    esac
done

if [[ -z "$LOCAL_DIR" || -z "$REMOTE_DIR" || -z "$REMOTE_USER" || -z "$REMOTE_HOST" ]]; then
    awk 'f && !/^#/{exit} /^# USAGE/{f=1} f{sub(/^# ?/,""); print}' "$0"
    exit 1
fi

# ── OS detection ──────────────────────────────────────────────
OS=$(uname -s)   # Darwin = macOS, Linux = Linux

# ── Colors ────────────────────────────────────────────────────
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

W_FILE=60
W_PERM=11
W_DATE=16
W_STATUS=13

# ── Temp files ────────────────────────────────────────────────
RSYNC_TMP=$(mktemp)
PARSED_TMP=$(mktemp)
LOCAL_STATS_TMP=$(mktemp)
REMOTE_STATS_TMP=$(mktemp)
MERGE_TMP=$(mktemp)
trap "rm -f '$RSYNC_TMP' '$PARSED_TMP' '$LOCAL_STATS_TMP' '$REMOTE_STATS_TMP' '$MERGE_TMP'" EXIT

# ── Step 1: rsync dry-run ─────────────────────────────────────
# -a archive  -v verbose  -z compress  -i itemize  -n dry-run  --delete show remote-only
# -c checksum  compare by content instead of timestamp+size (optional, slower)
RSYNC_CHECKSUM_FLAG=""
[[ "$CHECKSUM" == "true" ]] && RSYNC_CHECKSUM_FLAG="-c"
printf "  Running rsync dry-run...  "
rsync -avzin --delete --exclude 'envs/' $RSYNC_CHECKSUM_FLAG \
    "${LOCAL_DIR}/" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" 2>/dev/null \
    | grep -E '^(>f|\*deleting)' > "$RSYNC_TMP" || true
printf "${GREEN}%d changed files${NC}\n" "$(wc -l < "$RSYNC_TMP" | tr -d ' ')"

# ── Step 2: Parse rsync itemize output ───────────────────────
# Itemize format: 11-char code + space + filename
#   >f+++++++++ = new file (LOCAL ONLY — all flags are '+')
#   >f.st...... = file exists on both, size/time differ (LOCAL NEWER)
#   *deleting   = file exists on remote only (REMOTE ONLY)
while IFS= read -r line; do
    file="${line#* }"          # filename is everything after the first space
    code="${line:0:11}"
    if [[ "$line" == \*deleting* ]]; then
        printf "REMONLY\t%s\n" "$file"
    else
        suffix="${code:2}"     # change flags after ">f"
        if [[ "${suffix//+/}" == "" ]]; then
            printf "LOCONLY\t%s\n" "$file"
        else
            printf "GREEN\t%s\n" "$file"
        fi
    fi
done < "$RSYNC_TMP" | sort -t$'\t' -k2 > "$PARSED_TMP"

# ── Step 3: Gather local stats (macOS or Linux stat) ─────────
printf "  Gathering local stats...  "
grep -E '^(GREEN|LOCONLY)' "$PARSED_TMP" | cut -f2 | \
while IFS= read -r file; do
    full="$LOCAL_DIR/$file"
    if [[ "$OS" == "Darwin" ]]; then
        ts=$(stat -f "%m"                     "$full" 2>/dev/null || echo 0)
        perm=$(stat -f "%Sp"                  "$full" 2>/dev/null || echo '---')
        date_str=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$full" 2>/dev/null || echo '---')
    else
        ts=$(stat -c '%Y' "$full" 2>/dev/null || echo 0)
        perm=$(stat -c '%A' "$full" 2>/dev/null || echo '---')
        date_str=$(date -d "@$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '---')
    fi
    printf "%s|%s|%s|%s\n" "$file" "$ts" "$perm" "$date_str"
done > "$LOCAL_STATS_TMP"
printf "${GREEN}done${NC}\n"

# ── Step 4: Gather remote stats via single SSH call ───────────
NEEDS_REMOTE=$(grep -E '^(GREEN|REMONLY)' "$PARSED_TMP" | cut -f2 || true)

if [[ -n "$NEEDS_REMOTE" ]]; then
    printf "  Gathering remote stats... "
    ssh "${REMOTE_USER}@${REMOTE_HOST}" bash 2>/dev/null << REMOTE_SCRIPT > "$REMOTE_STATS_TMP"
while IFS= read -r f; do
    full="${REMOTE_DIR}/\$f"
    if [ -f "\$full" ]; then
        ts=\$(stat -c '%Y' "\$full" 2>/dev/null || echo 0)
        perm=\$(stat -c '%A' "\$full" 2>/dev/null || echo '---')
        date_str=\$(date -d "@\$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '---')
        printf '%s|%s|%s|%s\n' "\$f" "\$ts" "\$perm" "\$date_str"
    else
        printf '%s|0|---|---\n' "\$f"
    fi
done << 'FILELIST'
${NEEDS_REMOTE}
FILELIST
REMOTE_SCRIPT
    printf "${GREEN}done${NC}\n"
fi

# ── Step 5: Join and build final merge table ──────────────────
awk -v lstats="$LOCAL_STATS_TMP" -v rstats="$REMOTE_STATS_TMP" '
FILENAME == lstats { split($0,a,"|"); lperm[a[1]]=a[3]; ldate[a[1]]=a[4]; next }
FILENAME == rstats { split($0,a,"|"); rperm[a[1]]=a[3]; rdate[a[1]]=a[4]; next }
{
    split($0,a,"\t"); tag=a[1]; file=a[2]
    if      (tag == "LOCONLY") printf "%s\t%s\t%s\t%s\t---\t---\n",         tag, file, lperm[file], ldate[file]
    else if (tag == "REMONLY") printf "%s\t%s\t---\t---\t%s\t%s\n",         tag, file, rperm[file], rdate[file]
    else                       printf "%s\t%s\t%s\t%s\t%s\t%s\n",           tag, file, lperm[file], ldate[file], rperm[file], rdate[file]
}
' "$LOCAL_STATS_TMP" "$REMOTE_STATS_TMP" "$PARSED_TMP" > "$MERGE_TMP"

# ── Table header ──────────────────────────────────────────────
SEP_LEN=$(( W_FILE + W_PERM*2 + W_DATE*2 + W_STATUS + 14 ))
echo ""
printf "  ${BOLD}Local ${NC} : %s\n" "$LOCAL_DIR"
printf "  ${BOLD}Remote${NC} : %s@%s:%s\n" "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_DIR"
echo ""
printf "${BOLD}%-${W_FILE}s  %-${W_PERM}s  %-${W_DATE}s  %-${W_PERM}s  %-${W_DATE}s  %-${W_STATUS}s${NC}\n" \
    "FILE" "LOCAL PERMS" "LOCAL DATE" "REMOTE PERMS" "REMOTE DATE" "STATUS"
printf '%*s\n' "$SEP_LEN" '' | tr ' ' '─'

# ── Render rows ───────────────────────────────────────────────
while IFS=$'\t' read -r tag file lperm ldate rperm rdate; do
    case "$tag" in
        GREEN)   color="$GREEN";  status="LOCAL NEWER" ;;
        LOCONLY) color="$YELLOW"; status="LOCAL ONLY"  ;;
        REMONLY) color="$YELLOW"; status="REMOTE ONLY" ;;
        *)       color="$NC";     status="?"           ;;
    esac

    disp="$file"
    if (( ${#file} > W_FILE )); then
        disp="...${file: -$((W_FILE - 3))}"
    fi

    printf "${color}%-${W_FILE}s  %-${W_PERM}s  %-${W_DATE}s  %-${W_PERM}s  %-${W_DATE}s  %-${W_STATUS}s${NC}\n" \
        "$disp" "$lperm" "$ldate" "$rperm" "$rdate" "$status"
done < "$MERGE_TMP"

printf '%*s\n' "$SEP_LEN" '' | tr ' ' '─'

# ── Legend ────────────────────────────────────────────────────
echo ""
printf "${BOLD}LEGEND${NC}  "
printf "${GREEN}■ LOCAL NEWER${NC}  "
printf "${YELLOW}■ ONE SIDE ONLY${NC}\n"

# ── Summary ───────────────────────────────────────────────────
echo ""
printf "${BOLD}SUMMARY${NC}  "
printf "${GREEN}%d local newer${NC}  "  "$(grep -c '^GREEN'   "$MERGE_TMP" || true)"
printf "${YELLOW}%d local only${NC}  "  "$(grep -c '^LOCONLY' "$MERGE_TMP" || true)"
printf "${YELLOW}%d remote only${NC}\n" "$(grep -c '^REMONLY' "$MERGE_TMP" || true)"
printf "  ${BOLD}NOTE${NC} Remote-newer files are not shown — rsync compares local→remote only.\n"
