#!/usr/bin/env bash
# Clone a repository from the rabravo GitHub account.
#
# Usage:
#   ab_git_get_repo.sh <project-name> [target-directory]
#   ab_git_get_repo.sh --ssh <project-name> [target-directory]

set -euo pipefail

GITHUB_USER="rabravo"
HTTPS_BASE="https://github.com/${GITHUB_USER}"
SSH_BASE="git@github.com:${GITHUB_USER}"

show_help() {
cat << EOF
Usage: $(basename "$0") [--ssh] <project-name> [target-directory]

Clone a repository from the ${GITHUB_USER} GitHub account.

Arguments:
  project-name       Name of the repository (e.g. "my-project")
  target-directory   Optional local directory to clone into.
                     Defaults to the repository name.

Options:
  --ssh        Use SSH instead of HTTPS for cloning.
  -h, --help   Show this help message and exit.

Examples:
  $(basename "$0") my-project
  $(basename "$0") --ssh my-project
  $(basename "$0") my-project ~/projects/my-project
  $(basename "$0") --ssh my-project ~/projects/my-project
EOF
}

USE_SSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --ssh)     USE_SSH=true; shift ;;
    *)         break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Error: project name is required."
  show_help
  exit 1
fi

PROJECT="$1"
TARGET="${2:-}"

if [[ "$USE_SSH" == true ]]; then
  CLONE_URL="${SSH_BASE}/${PROJECT}.git"
else
  CLONE_URL="${HTTPS_BASE}/${PROJECT}.git"
fi

echo "Cloning: ${CLONE_URL}"
if [[ -n "$TARGET" ]]; then
  git clone "$CLONE_URL" "$TARGET"
else
  git clone "$CLONE_URL"
fi

echo "Done."
