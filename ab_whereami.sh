#!/bin/bash
# Determine the current working directory
CURRENT_DIR=$(pwd)

# Define your Apache root and domain
WEB_ROOT="/var/www/html"
DOMAIN="https://angelbravo.cloud"

# Verify we’re under the web root
if [[ $CURRENT_DIR == $WEB_ROOT* ]]; then
    # Remove the web root prefix
    RELATIVE_PATH=${CURRENT_DIR#$WEB_ROOT}

    # Construct full URL
    FULL_URL="${DOMAIN}${RELATIVE_PATH}"

    echo "$FULL_URL"
else
    echo "Error: You are not inside $WEB_ROOT"
    exit 1
fi
