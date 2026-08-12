#!/usr/bin/env bash
# Clone a repository from the rabravo GitHub account.
#
# Usage:
#   ab_git_get_repo.sh <project-name>
#   ab_git_get_repo.sh <project-name> [target-directory]

set -euo pipefail

GITHUB_USER="rabravo"
BASE_URL="https://github.com/${GITHUB_USER}"

show_help() {
cat << EOF
Usage: $(basename "$0") <project-name> [target-directory]

Clone a repository from the ${GITHUB_USER} GitHub account.

Arguments:
  project-name       Name of the repository (e.g. "my-project")
  target-directory   Optional local directory to clone into.
                     Defaults to the repository name.

Examples:
  $(basename "$0") my-project
  $(basename "$0") my-project ~/projects/my-project

Options:
  -h, --help   Show this help message and exit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "Error: project name is required."
  show_help
  exit 1
fi

PROJECT="$1"
CLONE_URL="${BASE_URL}/${PROJECT}.git"
TARGET="${2:-}"

echo "Cloning: ${CLONE_URL}"
if [[ -n "$TARGET" ]]; then
  git clone "$CLONE_URL" "$TARGET"
else
  git clone "$CLONE_URL"
fi

echo "Done."
