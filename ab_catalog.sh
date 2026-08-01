#!/usr/bin/env bash
# Fetch Oakland University course info from the Coursedog-powered catalog.
# Docs: coursedog-api-docs.html  (compare with digarc-api-docs.html for old API)
#
# Usage:
#   ./catalog.sh "CSI 3450"           # plain text output
#   ./catalog.sh "CSI 3450" --html    # generates doc_catalog.html
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: ./catalog.sh \"CSI 3450\" [--html [credits] [delivery]]"
    exit 1
fi

# Normalize input to uppercase and split into prefix + code ("CSI 3450" → CSI, 3450)
input="${1^^}"
if [[ ! "$input" =~ ^([A-Z]+)[[:space:]]+([0-9]+)$ ]]; then
    echo "Invalid format: '$1' (expected e.g. 'CSI 3450')"
    exit 1
fi

PREFIX="${BASH_REMATCH[1]}"
CODE="${BASH_REMATCH[2]}"

# Parse optional flags
HTML_MODE=false
[[ $# -ge 2 && "${2}" == "--html" ]] && HTML_MODE=true

# Courses with 2 credit hours — all others default to 4.
TWO_CREDIT_COURSES=()  # e.g. ("CSI1100" "MTH1000")

credits=4
for c in "${TWO_CREDIT_COURSES[@]}"; do
    [[ "${PREFIX}${CODE}" == "$c" ]] && credits=2 && break
done

# Direct detail URL — prefix and code are concatenated with no space.
# See coursedog-api-docs.html § "Course Detail":
#   GET /courses/{PREFIX}{CODE}  e.g. /courses/CSI3450
# The page is server-side rendered (SSR), so all course data is in the
# initial HTML response — no JavaScript execution needed.
URL="https://undergraduatecatalog.oakland.edu/courses/${PREFIX}${CODE}"

# A User-Agent header is required; without it the server returns sparse HTML.
# curl -f treats HTTP errors as failures; 2>/dev/null suppresses progress output.
html=$(curl -fsA "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" "$URL" 2>/dev/null) || {
    echo "No results found for ${PREFIX} ${CODE}"
    exit 1
}

# Normalize HTML: insert a newline at every tag boundary (><) so each tag
# and each text node end up on their own line. This lets grep/awk treat the
# document line-by-line without a real HTML parser.
norm=$(printf '%s' "$html" | sed 's/></>\n</g')

# Extract the course title from the <h2 class="heading-5 ..."> element.
# See coursedog-api-docs.html § "HTML Structure — Course title":
#   <h2 class="heading-5 mb-2" data-v-07aba0e5>CSI 3450 Database Dsgn &amp; Implementation</h2>
# We anchor on ^<h2 to skip the <style> block that also contains "heading-5".
# sed strips the opening tag and any closing tag, then decodes HTML entities.
title=$(printf '%s' "$norm" \
    | grep '^<h2 .*heading-5' \
    | head -1 \
    | sed 's/.*heading-5[^>]*>//; s/<.*//' \
    | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g')

# Extract field-label / value pairs into a tab-separated stream: "label\tvalue"
# See coursedog-api-docs.html § "HTML Structure — Field label + value pairs":
#   <h3 class="field-label">Course Description</h3>
#   <div class="field-value">Introduction to...</div>
#
# awk state machine:
#   - Line matches class="field-label"  → strip tags, save as label, set found=1
#   - Next non-empty line (found=1)     → strip tags/comments/entities, emit "label\tvalue"
# Blank lines and HTML comment nodes (<!----> placeholders from Vue) are skipped
# by the length>0 guard, so multi-line value divs still resolve correctly.
fields=$(printf '%s' "$norm" | awk '
/class="field-label"/ {
    label = $0
    gsub(/<[^>]*>/, "", label)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)
    found = 1
    next
}
found {
    gsub(/<[^>]*>/, "")           # strip all HTML tags
    gsub(/<!--[^-]*-->/, "")      # strip Vue SSR comment placeholders
    gsub(/&amp;/, "\\&")
    gsub(/&lt;/, "<")
    gsub(/&gt;/, ">")
    gsub(/^[[:space:]]+|[[:space:]]+$/, "")
    if (length > 0) {
        print label "\t" $0
        found = 0
    }
}
')

# Pull the full Course Description text (already scraped from the page).
# The catalog bundles description + requirements + prerequisites into one block, e.g.:
#   "...systems administration. Additional Requirement(s): major standing Prerequisite(s): CSI 2290 or CSI 2300"
# or with no space before Prerequisite(s) when there is no Additional Requirement:
#   "...CSI 5460.Prerequisite(s): CSI 2470"
description=$(printf '%s' "$fields" | awk -F'\t' '$1=="Course Description"{print $2}')

# Split description body from prerequisites by cutting at "Additional Requirement(s):"
# or "Prerequisite(s):". The pattern uses * (zero or more spaces) so it matches
# both "... standing Prerequisite(s):" and "...CSI 5460.Prerequisite(s):".
desc_body=$(printf '%s' "$description" \
    | sed 's/ *Additional Requirement(s):.*$//' \
    | sed 's/ *Prerequisite(s):.*$//')

# Extract everything after "Prerequisite(s):" from the same description text.
prereq=$(printf '%s' "$description" \
    | grep -o 'Prerequisite(s):.*' \
    | sed 's/Prerequisite(s): *//')

# ── Plain text output ──────────────────────────────────────────────────────────
if [[ "$HTML_MODE" == false ]]; then
    printf '%s\n\n' "$title"
    printf '%s' "$fields" | awk -F'\t' '{print $1 ": " $2}'
    exit 0
fi

# ── HTML output ────────────────────────────────────────────────────────────────
# Generates doc_catalog.html with rows:
#   Row 1 — description body (prerequisites stripped out)
#   Row 2 — prerequisite line (omitted if the course has none)
#   Row 3 — credit hours (hardcoded: TWO_CREDIT_COURSES → 2, all others → 4)
outfile="doc_catalog.html"

{
    printf '<!-- %s -->\n' "$outfile"
    printf '<h3>Course Catalog Description</h3>\n\n'
    printf '<div class="overflow-table">\n'
    printf '    <table class="info" border="4">\n'

    printf '        <tr>\n'
    printf '            <td>\n'
    printf '                %s\n' "$desc_body"
    printf '            </td>\n'
    printf '        </tr>\n\n'

    if [[ -n "$prereq" ]]; then
        printf '        <tr>\n'
        printf '            <td>Prerequisite: %s</td>\n' "$prereq"
        printf '        </tr>\n\n'
    fi

    printf '        <tr>\n'
    printf '            <td>%s Credit hours</td>\n' "${credits}.0"
    printf '        </tr>\n\n'

    printf '    </table>\n'
    printf '    <br>\n\n'
    printf '</div>\n'
} > "$outfile"

echo "Written: $outfile"
