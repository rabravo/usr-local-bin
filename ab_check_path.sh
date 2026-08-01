#!/usr/bin/env bash

target="$1"

if [[ -z "$target" ]]; then
  echo "Usage: $0 /path/to/check"
  exit 1
fi

if [[ ! "$target" =~ ^/[a-zA-Z0-9/_.\-]*$ ]]; then
  echo "Error: '$target' does not look like a valid absolute path"
  echo "Usage: $0 /path/to/check"
  exit 1
fi

IFS=':' read -r -a path_entries <<< "$PATH"

for entry in "${path_entries[@]}"; do
  if [[ "$entry" == "$target" ]]; then
    echo "Found in PATH: $target"
    exit 0
  fi
done

echo "Not found in PATH: $target"
exit 1
