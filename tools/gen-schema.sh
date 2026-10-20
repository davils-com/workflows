#!/usr/bin/env bash
# Regenerates schemas/davils-ci.schema.json from actions/resolve-config/defaults.yaml.
# With --check it only fails when the committed schema is stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
generated="$(yq -o=json actions/resolve-config/defaults.yaml | python3 tools/gen-schema.py)"
if [[ "${1:-}" == --check ]]; then
  if ! diff -u schemas/davils-ci.schema.json <(printf '%s\n' "$generated"); then
    echo "::error::schemas/davils-ci.schema.json is stale; run tools/gen-schema.sh." >&2
    exit 1
  fi
else
  printf '%s\n' "$generated" >schemas/davils-ci.schema.json
fi
