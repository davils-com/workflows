#!/usr/bin/env bash
# Fails when an action or reusable workflow is referenced without a full commit SHA.
#
# Allowed: $/... (this repository at the running commit), ./... (only in examples and tests) and
# owner/repo[/path]@<40 hex characters> # <version>. Docker images of workflows are checked by
# zizmor; the Writerside builder image is pinned by its version tag on purpose (see
# self-update-pins.yml).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
while IFS= read -r line; do
  file="${line%%:*}"
  rest="${line#*:}"
  number="${rest%%:*}"
  ref="$(sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]]+#.*//; s/^["'"'"']//; s/["'"'"']$//' <<<"${rest#*:}")"
  case "$ref" in
    '$/'* | ./*) continue ;;
    docker://*) continue ;;
  esac
  # The examples follow a major release of this repository, as consumers usually do.
  if [[ "$file" == examples/* && "$ref" =~ ^davils-com/workflows/.+@v[0-9]+$ ]]; then
    continue
  fi
  if [[ ! "$ref" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$ ]]; then
    echo "::error file=$file,line=$number::$ref is not pinned by a full commit SHA."
    status=1
  elif ! grep -qE '#[[:space:]]*v?[0-9]' <<<"${rest#*:}"; then
    echo "::error file=$file,line=$number::$ref has no version comment (# vX.Y.Z)."
    status=1
  fi
done < <(grep -rnE '^[[:space:]-]*uses:' .github/workflows actions examples 2>/dev/null)
exit "$status"
