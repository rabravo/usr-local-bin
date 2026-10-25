#!/usr/bin/env bash
# Query the Poetry Foundation Glossary for a term definition.
# Usage: ab_poetry_glossary.sh <term>

set -euo pipefail

BASE_URL="https://www.poetryfoundation.org/education/glossary"

usage() {
  echo "Usage: $(basename "$0") <term>"
  echo "Example: $(basename "$0") madrigal"
  exit 1
}

[[ $# -lt 1 ]] && usage

TERM="${1,,}"                        # lowercase
SLUG="${TERM// /-}"                  # spaces → hyphens
URL="${BASE_URL}/${SLUG}"

if ! command -v lynx &>/dev/null; then
  echo "Error: 'lynx' is required but not installed." >&2
  echo "Install with: brew install lynx" >&2
  exit 2
fi

RAW=$(lynx -dump -nolist "$URL" 2>/dev/null || true)

if [[ -z "$RAW" ]]; then
  echo "Error: Could not fetch '$URL'." >&2
  exit 3
fi

NOT_FOUND=$(echo "$RAW" | LC_ALL=C grep "Page not found (404" | wc -l || true)
if [[ "$NOT_FOUND" -gt 0 ]]; then
  echo "Term '${TERM}' was not found in the Poetry Foundation glossary." >&2
  echo "Browse all terms: https://www.poetryfoundation.org/education/glossary" >&2
  exit 4
fi

# Extract: lines between "Share thisShare" sentinel and "Browse all terms",
# skipping the repeated title line (matches slug, case-insensitive)
DEFINITION=$(echo "$RAW" \
  | LC_ALL=C awk -v slug="$SLUG" \
      'BEGIN{slug_upper=toupper(substr(slug,1,1)) substr(slug,2)}
       /Share thisShare/{found=1; next}
       found && /Browse all terms/{exit}
       found && /[^[:space:]]/{
         gsub(/^[[:space:]]+/,"");
         if (tolower($0) == tolower(slug_upper)) next;
         print
       }' \
  | LC_ALL=C grep -v '^\*$')

if [[ -z "$DEFINITION" ]]; then
  echo "No definition found for '${TERM}'." >&2
  exit 4
fi

TITLE=$(echo "$TERM" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')
echo ""
echo "${TITLE}"
echo "${DEFINITION}"
echo ""
