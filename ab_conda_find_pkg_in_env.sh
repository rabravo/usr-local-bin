#!/usr/bin/env bash

# ============================================================
# Check which conda environments contain a specific package
# Prints only environments where the package is found.
# Usage:
#   ./script pandas
# ============================================================

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
  # Capture only the package rows (ignore headers and empty lines)
  PKG_INFO=$(conda list -n "$ENV" "$PACKAGE_NAME" 2>/dev/null | awk 'NR>2 && $1!="" {print $1, $2, $3}')

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
