#!/usr/bin/env bash
# Waits until the versions of the sibling packages a package depends on are on pub.dev.
#
# When the tags of several packages of a workspace are pushed together, their releases run at the
# same time; a package can only be published once the lowest version of every sibling it depends
# on is there. Siblings are the packages of the repository; others are not waited for.
#
# Environment:
#   PACKAGE_PATH   directory of the package's pubspec.yaml
#   SIBLINGS       JSON array of the names of the packages of the repository
#   ATTEMPTS       how often to ask pub.dev (default 60)
#   INTERVAL       seconds between two attempts (default 30)
#   PUB_URL        the package host (default https://pub.dev)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

pubspec="${PACKAGE_PATH:?PACKAGE_PATH is required}/pubspec.yaml"
siblings="${SIBLINGS:-[]}"
attempts="${ATTEMPTS:-60}"
interval="${INTERVAL:-30}"
host="${PUB_URL:-https://pub.dev}"
host="${host%/}"

wanted="$(yq -o=json -I=0 '.dependencies // {}' "$pubspec" | jq -c -L "$here/../../_lib" --argjson siblings "$siblings" '
  include "lib";
  to_entries | map(select(.key as $k | $siblings | index($k)) | select(.value | type == "string")
    | {name: .key, version: lower_bound(.value)} | select(.version != null))
')"

if [[ "$(jq 'length' <<<"$wanted")" == 0 ]]; then
  echo "The package depends on no sibling by version; nothing to wait for."
  exit 0
fi

while IFS= read -r dependency; do
  name="$(jq -r '.name' <<<"$dependency")"
  version="$(jq -r '.version' <<<"$dependency")"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS -o /dev/null "$host/api/packages/$name/versions/$version"; then
      echo "$name $version is on $host."
      continue 2
    fi
    echo "Waiting for $name $version on $host ($attempt/$attempts)."
    ((attempt < attempts)) && sleep "$interval"
  done
  die "$name $version did not reach $host. Publish it first, or push its tag together with this one."
done < <(jq -c '.[]' <<<"$wanted")
