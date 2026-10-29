#!/bin/bash
CURRENT_DIR=$(pwd)

# Apache document root and its domain
WEB_ROOT="/var/www/html"
DOMAIN="https://angelbravo.cloud"

# Optional override: set this if hostname -f doesn’t match Apache’s ServerName
SERVER_NAME_OVERRIDE=""

# userdir public_html root for the current user
USER_PUBLIC_HTML="${HOME}/public_html"

if [[ $CURRENT_DIR == $WEB_ROOT* ]]; then
    RELATIVE_PATH=${CURRENT_DIR#$WEB_ROOT}
    echo "${DOMAIN}${RELATIVE_PATH}"

elif [[ $CURRENT_DIR == $USER_PUBLIC_HTML* ]]; then
    if [[ -n $SERVER_NAME_OVERRIDE ]]; then
        SERVER_NAME="$SERVER_NAME_OVERRIDE"
    else
        SERVER_NAME=$(hostname -f 2>/dev/null || hostname)
    fi
    RELATIVE_PATH=${CURRENT_DIR#$USER_PUBLIC_HTML}
    echo "http://${SERVER_NAME}/~${USER}${RELATIVE_PATH}"

else
    echo "Error: You are not inside $WEB_ROOT or $USER_PUBLIC_HTML"
    exit 1
fi
