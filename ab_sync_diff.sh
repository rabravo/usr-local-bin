#!/usr/bin/env bash
# ab_sync_diff.sh — Color-coded diff table between a local dir and a remote dir over SSH
#
# USAGE
#   ./ab_sync_diff.sh -l PATH -r PATH -u USER -s HOST [--all]
#
# All four path/connection flags are required. Running the script with no
# arguments (or missing any required flag) prints this help and exits.
#
# DESCRIPTION
#   Compares file timestamps and permissions between a local directory and a
#   remote directory over SSH. Outputs a color-coded table showing which files
#   are newer locally, newer on the remote, or only present on one side.
#   In-sync files are hidden by default to keep output focused on differences.
#   Automatically detects macOS vs Linux to handle stat command differences.
#   SSH banner and connection messages are suppressed automatically.
#
# REQUIRED FLAGS
#   -l, --local  PATH   Local directory to compare
#   -r, --remote PATH   Absolute path of the remote directory
#   -u, --user   USER   SSH username on the remote server
#   -s, --server HOST   Remote hostname or IP address
#
# OPTIONAL FLAGS
#   -a, --all           Also show files that are already in sync
#   -h, --help          Show this help message and exit
#
# OUTPUT COLUMNS
#   FILE          Relative file path (truncated with ... if wider than column)
#   LOCAL PERMS   Permission bits of the local file  (e.g. -rw-r--r--)
#   LOCAL DATE    Last-modified timestamp of the local file
#   REMOTE PERMS  Permission bits of the remote file
#   REMOTE DATE   Last-modified timestamp of the remote file
#   STATUS        One of: LOCAL NEWER, REMOTE NEWER, LOCAL ONLY, REMOTE ONLY, IN SYNC
#
# COLOR CODING
#   Green   Local file is newer than the remote copy
#   Red     Remote file is newer than the local copy
#   Yellow  File exists on only one side (local only or remote only)
#   Dim     Files are identical in timestamp (shown only with --all)
#
# EXAMPLES
#   ./ab_sync_diff.sh -l ~/myproject -r /remote/myproject -u alice -s hpc.university.edu
#       Basic usage — show only files that differ
#
#   ./ab_sync_diff.sh -l ~/myproject -r /remote/myproject -u alice -s hpc.university.edu --all
#       Show every file including those already in sync
#
#   ./ab_sync_diff.sh -l ~/myproject -r /remote/myproject -u alice -s hpc.university.edu | less -R
#       Scroll through a long output while preserving colors

# ── Argument parsing ──────────────────────────────────────────
LOCAL_DIR=""
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_DIR=""
SHOW_SYNCED=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--local)   LOCAL_DIR="$2";   shift 2 ;;
        -r|--remote)  REMOTE_DIR="$2";  shift 2 ;;
        -u|--user)    REMOTE_USER="$2"; shift 2 ;;
        -s|--server)  REMOTE_HOST="$2"; shift 2 ;;
        -a|--all)     SHOW_SYNCED=true; shift ;;
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
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

W_FILE=60
W_PERM=11
W_DATE=16
W_STATUS=13

LOCAL_TMP=$(mktemp)
REMOTE_TMP=$(mktemp)
MERGE_TMP=$(mktemp)
trap "rm -f '$LOCAL_TMP' '$REMOTE_TMP' '$MERGE_TMP'" EXIT

# ── Gather local files ────────────────────────────────────────
printf "  Gathering local files...  "
find "$LOCAL_DIR" -type d -name envs -prune -o -type f -print | while IFS= read -r f; do
    rel="${f#$LOCAL_DIR/}"
    if [[ "$OS" == "Darwin" ]]; then
        ts=$(stat -f "%m" "$f")
        perm=$(stat -f "%Sp" "$f")
        date_str=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f")
    else
        ts=$(stat -c '%Y' "$f")
        perm=$(stat -c '%A' "$f")
        date_str=$(date -d "@$ts" '+%Y-%m-%d %H:%M')
    fi
    printf "%s|%s|%s|%s\n" "$rel" "$ts" "$perm" "$date_str"
done | sort > "$LOCAL_TMP"
printf "${GREEN}%d files${NC}\n" "$(wc -l < "$LOCAL_TMP" | tr -d ' ')"

# ── Gather remote files via SSH ───────────────────────────────
printf "  Gathering remote files... "
ssh "${REMOTE_USER}@${REMOTE_HOST}" bash -s 2>/dev/null << REMOTE_SCRIPT > "$REMOTE_TMP"
find "${REMOTE_DIR}" -type d -name envs -prune -o -type f -print 2>/dev/null | while IFS= read -r f; do
    rel="\${f#${REMOTE_DIR}/}"
    ts=\$(stat -c '%Y' "\$f" 2>/dev/null || echo 0)
    perm=\$(stat -c '%A' "\$f" 2>/dev/null || echo '----------')
    date_str=\$(date -d "@\$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'unknown')
    printf "%s|%s|%s|%s\n" "\$rel" "\$ts" "\$perm" "\$date_str"
done | sort
REMOTE_SCRIPT
printf "${GREEN}%d files${NC}\n" "$(wc -l < "$REMOTE_TMP" | tr -d ' ')"

# ── Merge local + remote, tag each row ───────────────────────
awk -F'|' '
NR == FNR {
    lts[$1] = $2; lperm[$1] = $3; ldate[$1] = $4
    next
}
{
    file = $1; rts = $2; rperm = $3; rdate = $4
    seen[file] = 1
    if (file in lts) {
        if      (lts[file]+0 > rts+0) tag = "GREEN"
        else if (rts+0 > lts[file]+0) tag = "RED"
        else                           tag = "DIM"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", tag, file, lperm[file], ldate[file], rperm, rdate
    } else {
        printf "REMONLY\t%s\t---\t---\t%s\t%s\n", file, rperm, rdate
    }
}
END {
    for (f in lts)
        if (!(f in seen))
            printf "LOCONLY\t%s\t%s\t%s\t---\t---\n", f, lperm[f], ldate[f]
}
' "$LOCAL_TMP" "$REMOTE_TMP" | sort -t$'\t' -k2 > "$MERGE_TMP"

# ── Print connection info ─────────────────────────────────────
echo ""
printf "  ${BOLD}Local ${NC} : %s\n" "$LOCAL_DIR"
printf "  ${BOLD}Remote${NC} : %s@%s:%s\n" "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_DIR"

# ── Table header ──────────────────────────────────────────────
SEP_LEN=$(( W_FILE + W_PERM*2 + W_DATE*2 + W_STATUS + 14 ))
echo ""
printf "${BOLD}%-${W_FILE}s  %-${W_PERM}s  %-${W_DATE}s  %-${W_PERM}s  %-${W_DATE}s  %-${W_STATUS}s${NC}\n" \
    "FILE" "LOCAL PERMS" "LOCAL DATE" "REMOTE PERMS" "REMOTE DATE" "STATUS"
printf '%*s\n' "$SEP_LEN" '' | tr ' ' '─'

# ── Render rows ───────────────────────────────────────────────
while IFS=$'\t' read -r tag file lperm ldate rperm rdate; do
    case "$tag" in
        GREEN)   color="$GREEN";  status="LOCAL NEWER"  ;;
        RED)     color="$RED";    status="REMOTE NEWER" ;;
        DIM)     color="$DIM";    status="IN SYNC"      ;;
        LOCONLY) color="$YELLOW"; status="LOCAL ONLY"   ;;
        REMONLY) color="$YELLOW"; status="REMOTE ONLY"  ;;
        *)       color="$NC";     status="?"            ;;
    esac

    [[ "$tag" == "DIM" && "$SHOW_SYNCED" == "false" ]] && continue

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
printf "${RED}■ REMOTE NEWER${NC}  "
printf "${YELLOW}■ ONE SIDE ONLY${NC}  "
printf "${DIM}■ IN SYNC${NC}\n"

# ── Summary counts ────────────────────────────────────────────
echo ""
printf "${BOLD}SUMMARY${NC}  "
printf "${GREEN}%d local newer${NC}  "  "$(grep -c '^GREEN'   "$MERGE_TMP" || true)"
printf "${RED}%d remote newer${NC}  " "$(grep -c '^RED'     "$MERGE_TMP" || true)"
printf "${YELLOW}%d local only${NC}  "  "$(grep -c '^LOCONLY' "$MERGE_TMP" || true)"
printf "${YELLOW}%d remote only${NC}  " "$(grep -c '^REMONLY' "$MERGE_TMP" || true)"
printf "${DIM}%d in sync${NC}\n"      "$(grep -c '^DIM'     "$MERGE_TMP" || true)"
[[ "$SHOW_SYNCED" == "false" ]] && printf "  ${DIM}(run with -a / --all to include in-sync files)${NC}\n"
