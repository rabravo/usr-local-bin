#!/usr/bin/env bash

# Defaults (used if args not provided)
DEFAULT_CORRECT_EMAIL="angel.bravo@unt.edu"
DEFAULT_BAD_EMAIL="angel.bravo@unt.eduangel.bravo@unt.eduangel.bravo@unt.edu"

show_help() {
cat << EOF
Usage: $(basename "$0") [CORRECT_EMAIL] [INCORRECT_EMAIL]

Rewrites Git history to replace an incorrect author/committer email with a corrected email.

Arguments (positional):
  CORRECT_EMAIL    The email you want to set (replacement).
                   Default: "$DEFAULT_CORRECT_EMAIL"

  INCORRECT_EMAIL  The email string to search for and replace.
                   Default: "$DEFAULT_BAD_EMAIL"

Options:
  -h, --help       Show this help message and exit.

Examples:
  # Use defaults (fix the repeated-email case to $DEFAULT_CORRECT_EMAIL)
  $(basename "$0")

  # Provide only correct email (incorrect email uses default)
  $(basename "$0") "angel.bravo@unt.edu"

  # Provide both correct and incorrect emails
  $(basename "$0") "angel.bravo@unt.edu" "bad@ex.combad@ex.com"

WARNING:
  This rewrites Git history and changes commit hashes.
  If this repository has been pushed to a remote, you will need to force push:

      git push origin --force --all
      git push origin --force --tags

Run this from the root of your Git repository.
EOF
}

# Help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# Args (order: correct, incorrect) with defaults
CORRECT_EMAIL="${1:-$DEFAULT_CORRECT_EMAIL}"
BAD_EMAIL="${2:-$DEFAULT_BAD_EMAIL}"

# Ensure we are inside a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Not inside a Git repository."
  exit 1
fi

echo "Replacing:"
echo "  $BAD_EMAIL"
echo "With:"
echo "  $CORRECT_EMAIL"
echo ""
read -r -p "Proceed? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

git filter-branch --env-filter "
if [ \"\$GIT_AUTHOR_EMAIL\" = \"$BAD_EMAIL\" ]; then
  export GIT_AUTHOR_EMAIL=\"$CORRECT_EMAIL\"
  export GIT_COMMITTER_EMAIL=\"$CORRECT_EMAIL\"
fi
" --tag-name-filter cat -- --branches --tags

echo ""
echo "Done."
echo "Verify with:"
echo "  git log --format='%an <%ae>' | sort -u"
