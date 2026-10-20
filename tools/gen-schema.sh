#!/usr/bin/env bash
# Regenerates schemas/davils-ci.schema.json from actions/resolve-config/defaults.yaml.
# With --check it only fails when the committed schema is stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
generated="$(yq -o=json actions/resolve-config/defaults.yaml | python3 tools/gen-schema.py)"
if [[ "${1:-}" == --check ]]; then
  # shellcheck source=drift.sh
  source tools/drift.sh
  if ! difference="$(diff -u schemas/davils-ci.schema.json <(printf '%s\n' "$generated"))"; then
    report_drift schemas/davils-ci.schema.json tools/gen-schema.sh "$difference"
    exit 1
  fi
else
  printf '%s\n' "$generated" >schemas/davils-ci.schema.json
fi
