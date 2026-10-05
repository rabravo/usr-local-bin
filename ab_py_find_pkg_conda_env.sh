#!/usr/bin/env bash

# ============================================================
# Check which conda environments contain a specific package
# Prints only environments where the package is found.
# Usage:
#   ./ab_py_find_pkg_conda_env.sh pandas
# ============================================================

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  cat <<EOF
Usage: $0 <package-name>

Search all conda environments for a specific Python package and print
the environments where it is installed, along with its version and build.

Arguments:
  <package-name>   Exact name of the conda/pip package to search for
                   (e.g. pandas, numpy, scipy)

Options:
  -h, --help       Show this help message and exit

Examples:
  $0 pandas
  $0 numpy
EOF
  exit 0
fi

PACKAGE_NAME="$1"

if [ -z "$PACKAGE_NAME" ]; then
  echo "❌ Please provide a package name."
  echo "Usage: $0 <package-name>"
  exit 1
fi

echo "🔍 Searching for '$PACKAGE_NAME' in all conda environments..."
echo "=============================================================="

# Get all environment names (including base)
ENVS=$(conda env list | awk '{print $1}' | grep -v '^#' | grep -v '^$')

FOUND_ENV=false

for ENV in $ENVS; do
  # Capture only the exact-match package row (skip comment/header lines)
  PKG_INFO=$(conda list -n "$ENV" "^${PACKAGE_NAME}$" 2>/dev/null | awk '/^#/{next} $1!="" {print $1, $2, $3}')

  # Only print if actual package info exists
  if [ -n "$PKG_INFO" ]; then
    FOUND_ENV=true
    echo -e "\n🧩 Environment: $ENV"
    echo "$PKG_INFO"
  fi
done

if [ "$FOUND_ENV" = false ]; then
  echo "🚫 '$PACKAGE_NAME' not found in any conda environment."
fi

echo -e "\n✅ Done."
