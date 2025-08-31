#!/bin/bash

# ========================
# Database Backup Script
# ========================

usage() {
    echo "Usage: $0 -d DATABASE [OPTIONS]"
    echo
    echo "This script dumps a MySQL database, stores it as a SQL file,"
    echo "and commits the backup to Git with a custom or default message."
    echo
    echo "Required:"
    echo "  -d DATABASE  Name of the database to back up"
    echo
    echo "Options:"
    echo "  -f FILE      SQL file name (default: DATABASE.sql)"
    echo "  -u USER      Database username (default: abravo)"
    echo "  -h           Show this help message and exit"
    echo
    echo "Example:"
    echo "  $0 -d mydb -f backup.sql -u myuser"
    exit 1
}

# Default values
USER="abravo"
DB=""
FILE=""

# Parse options
while getopts ":d:f:u:h" opt; do
  case $opt in
    d) DB="$OPTARG" ;;
    f) FILE="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# Make sure database name is provided
if [ -z "$DB" ]; then
  echo "Error: Database name is required."
  usage
fi

# If FILE not given, default to DATABASE.sql
if [ -z "$FILE" ]; then
  FILE="$DB.sql"
fi

# Dump database (simulate try/catch by checking exit code)
echo "Backing up database '$DB'..."
if ! mysqldump -u "$USER" -p "$DB" > "$FILE"; then
  echo "❌ Error: Failed to back up database '$DB'."
  echo "   Possible reasons: database does not exist, wrong user, or invalid password."
  exit 1
fi

# Get backup date
BK_DATE=$(date --date="@$(stat -c "%Y" "$FILE")" -Idate)

echo "Committing $FILE.$BK_DATE ..."

# Ask user for custom commit message
read -p "Enter a commit message (leave blank for default): " USER_MSG

# Use default if user leaves it blank
if [ -z "$USER_MSG" ]; then
    COMMIT_MSG="Backup $DB date: $BK_DATE"
else
    COMMIT_MSG="$USER_MSG"
fi

# Check for changes
if git status --porcelain | grep .; then
  git add .
  git commit -m "$COMMIT_MSG"
  echo "✅ Changes committed successfully with message: '$COMMIT_MSG'"
else
  echo "No changes to commit."
fi
