#!/usr/bin/env bash
# Regenerates the reference topics in docs/topics/reference from the workflows, the composite
# actions and the configuration defaults. With --check it only fails when they are stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

collect() {
  local workflows='{}' actions='{}' file
  for file in .github/workflows/*.yml; do
    workflows="$(jq -c --arg k "$(basename "$file")" --argjson v "$(yq -o=json -I=0 '.' "$file")" '.[$k] = $v' <<<"$workflows")"
  done
  for file in actions/*/action.yml; do
    actions="$(jq -c --arg k "$(basename "$(dirname "$file")")" --argjson v "$(yq -o=json -I=0 '.' "$file")" '.[$k] = $v' <<<"$actions")"
  done
  jq -cn --argjson workflows "$workflows" --argjson actions "$actions" \
    --arg defaults_yaml "$(cat actions/resolve-config/defaults.yaml)" \
    --slurpfile schema schemas/davils-ci.schema.json \
    '{workflows: $workflows, actions: $actions, defaults_yaml: $defaults_yaml, schema: $schema[0]}'
}

if [[ "${1:-}" == --check ]]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  collect | python3 tools/gen-docs.py "$work" "$PWD" >/dev/null
  # shellcheck source=drift.sh
  source tools/drift.sh
  if ! difference="$(diff -ru docs/topics/reference "$work")"; then
    report_drift docs/topics/reference tools/gen-docs.sh "$difference"
    exit 1
  fi
else
  rm -rf docs/topics/reference
  collect | python3 tools/gen-docs.py docs/topics/reference "$PWD"
fi
