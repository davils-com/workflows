#!/usr/bin/env bash
# Fails on em dashes in the text of this repository; the house style uses a colon, a semicolon or
# a new sentence instead.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
dash="$(printf '\xe2\x80\x94')"
if git ls-files 2>/dev/null | grep -q .; then
  files="$(git ls-files)"
else
  files="$(find . -type f -not -path './.git/*' -not -path '*/.dart_tool/*' -not -name LICENSE)"
fi
# shellcheck disable=SC2086
if matches="$(grep -n -- "$dash" $files 2>/dev/null)"; then
  while IFS= read -r match; do
    echo "::error file=${match%%:*}::An em dash; use a colon, a semicolon or a new sentence."
  done <<<"$matches"
  echo "$matches"
  exit 1
fi
