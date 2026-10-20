#!/usr/bin/env bash
# Regenerates the reference topics in docs/topics/reference from the workflows, the composite
# actions and the configuration defaults. With --check it only fails when they are stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Writes the workflows, actions, defaults and schema as files into a directory; passing them as
# arguments would hit Linux's limit of 128 KB per argument.
collect() {
  local into="$1" file
  mkdir -p "$into/workflows" "$into/actions"
  for file in .github/workflows/*.yml; do
    yq -o=json '.' "$file" >"$into/workflows/$(basename "$file").json"
  done
  for file in actions/*/action.yml; do
    yq -o=json '.' "$file" >"$into/actions/$(basename "$(dirname "$file")").json"
  done
  cp actions/resolve-config/defaults.yaml "$into/defaults.yaml"
  cp schemas/davils-ci.schema.json "$into/schema.json"
}

if [[ "${1:-}" == --check ]]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  collect "$work/input"
  python3 tools/gen-docs.py "$work/input" "$work/output" "$PWD" >/dev/null
  # shellcheck source=drift.sh
  source tools/drift.sh
  if ! difference="$(diff -ru docs/topics/reference "$work/output")"; then
    report_drift docs/topics/reference tools/gen-docs.sh "$difference"
    exit 1
  fi
else
  input="$(mktemp -d)"
  trap 'rm -rf "$input"' EXIT
  collect "$input"
  rm -rf docs/topics/reference
  python3 tools/gen-docs.py "$input" docs/topics/reference "$PWD"
fi
