#!/usr/bin/env bash

# ---------------------------------------------------------------
# ab_img_rename_clean.sh
#
# Rename files by:
#   • converting filenames to lowercase
#   • replacing spaces with underscores
#
# Options:
#   --help       Show usage
#   --dry-run    Show what would happen but make no changes
#   --recursive  Process subdirectories (walk tree)
#
# Usage:
#   ./ab_img_rename_clean.sh --dry-run
#   ./ab_img_rename_clean.sh --recursive
#   ./ab_img_rename_clean.sh --recursive --dry-run
#   ./ab_img_rename_clean.sh [OPTIONS] FILE
# ---------------------------------------------------------------

DRYRUN=false
RECURSIVE=false
TARGET_FILE=""

# --- Require at least one argument ---
if [[ $# -eq 0 ]]; then
    echo "Usage: ./ab_img_rename_clean.sh [OPTIONS] [FILE]"
    echo "Try:   ./ab_img_rename_clean.sh --help"
    exit 1
fi

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat <<EOF
ab_img_rename_clean.sh

This script renames files by:
  - converting filenames to lowercase
  - replacing spaces with underscores

Options:
  --help        Show this help message
  --dry-run     Print actions but do NOT rename files
  --recursive   Process files inside subdirectories

Examples:
  ./ab_img_rename_clean.sh --dry-run
  ./ab_img_rename_clean.sh --recursive
  ./ab_img_rename_clean.sh --recursive --dry-run
  ./ab_img_rename_clean.sh "My Photo.JPG"
  ./ab_img_rename_clean.sh --dry-run "My Photo.JPG"

EOF
            exit 0
            ;;
        --dry-run)
            DRYRUN=true
            ;;
        --recursive)
            RECURSIVE=true
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Try: ./ab_img_rename_clean.sh --help"
            exit 1
            ;;
        *)
            TARGET_FILE="$1"
            ;;
    esac
    shift
done


# -------------------------------------------------------
# Function: rename a single file
# -------------------------------------------------------
rename_file() {
    local f="$1"
    local new

    # prevent renaming directories, only files
    [[ -d "$f" ]] && return

    new=$(echo "$f" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

    if [[ "$f" != "$new" ]]; then
        if [[ "$DRYRUN" == true ]]; then
            echo "DRY-RUN: would rename '$f' -> '$new'"
        else
            echo "Renaming: '$f' -> '$new'"
            mv "$f" "$new"
        fi
    fi
}


# -------------------------------------------------------
# MAIN: single file passed as argument
# -------------------------------------------------------
if [[ -n "$TARGET_FILE" ]]; then
    rename_file "$TARGET_FILE"
    exit 0
fi


# -------------------------------------------------------
# MAIN: non-recursive mode
# -------------------------------------------------------
if [[ "$RECURSIVE" == false ]]; then
    for f in *; do
        [[ -e "$f" ]] || continue
        rename_file "$f"
    done
    exit 0
fi


# -------------------------------------------------------
# MAIN: recursive mode
# -------------------------------------------------------
# Use find to walk directories safely
find . -type f | while read -r filepath; do
    # Remove leading ./ for cleaner processing
    file="${filepath#./}"
    rename_file "$file"
done
