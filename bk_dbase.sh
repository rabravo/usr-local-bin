#!/bin/bash

# ========================
# Database Backup Script
# ========================

usage() {
    echo "Usage: $0 -d DATABASE [OPTIONS]"
    echo
    echo "This script dumps a MySQL database, stores it as a SQL file,"
    echo "commits the backup to Git with a custom or default message,"
    echo "and then pushes to the repo's upstream."
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

# Ensure database name is provided
if [ -z "$DB" ]; then
  echo "Error: Database name is required."
  usage
fi

# Default filename if not provided
if [ -z "$FILE" ]; then
  FILE="$DB.sql"
fi

# Dump database (check for failure like try/catch)
echo "Backing up database '$DB' to '$FILE'..."
if ! mysqldump -u "$USER" -p "$DB" > "$FILE"; then
  echo "❌ Error: Failed to back up database '$DB'."
  echo "   Possible reasons: database does not exist, wrong user, or invalid password."
  exit 1
fi

# Use current date for commit metadata (simple & portable)
BK_DATE=$(date -Idate)
echo "Preparing Git commit for $FILE (date: $BK_DATE)..."

# Ask user for custom commit message
read -p "Enter a commit message (leave blank for default): " USER_MSG
if [ -z "$USER_MSG" ]; then
    COMMIT_MSG="Backup $DB date: $BK_DATE"
else
    COMMIT_MSG="$USER_MSG"
fi

# Track commit status
COMMITTED=false

# Stage & commit if there are changes
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git status --porcelain | grep -q .; then
    git add "$FILE"
    if git commit -m "$COMMIT_MSG"; then
      echo "✅ Local commit created with message: '$COMMIT_MSG'"
      COMMITTED=true
    else
      echo "❌ Error: Git commit failed."
    fi
  else
    echo "ℹ️ No changes detected. Nothing to commit."
  fi
else
  echo "❌ Error: Current directory is not a Git repository. Skipping commit and push."
  exit 1
fi

# Inform user about local commit result before pushing
if [ "$COMMITTED" = true ]; then
  echo "📌 Local commit was successful."
else
  echo "📌 No new local commit was created."
fi

# Attempt to push regardless (useful if there were pending local commits)
echo "Pushing to upstream..."
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  if git push; then
    echo "✅ Push to upstream completed."
  else
    echo "❌ Error: Failed to push to upstream."
    echo "   Tip: Check your network, credentials, and permissions."
    exit 1
  fi
else
  echo "❌ Error: No upstream set for the current branch."
  echo "   Tip: Set it with: git push -u origin <branch>"
  exit 1
fi
