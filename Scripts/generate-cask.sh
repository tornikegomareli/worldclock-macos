#!/bin/bash
set -euo pipefail
[[ $# == 3 && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && -f "$2" ]] || {
  echo 'Usage: bash Scripts/generate-cask.sh VERSION DMG OUTPUT' >&2; exit 1;
}
version="$1"
digest="$(shasum -a 256 "$2" | awk '{print $1}')"
# Generate only from an actual release artifact. Never use an unchecked hash.
sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$digest/g" \
  "$(dirname "$0")/../Casks/worldclock.rb.in" > "$3"
