#!/usr/bin/env bash
# Regenerates .github/workflows/flutter-ci.yml from the inputs of dart-ci.yml.
# With --check it only fails when the committed file is stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
generated="$(yq -o=json '.on.workflow_call.inputs' .github/workflows/dart-ci.yml | python3 tools/gen-flutter-ci.py)"
if [[ "${1:-}" == --check ]]; then
  if ! diff -u .github/workflows/flutter-ci.yml <(printf '%s\n' "$generated"); then
    echo "::error::.github/workflows/flutter-ci.yml is stale; run tools/gen-flutter-ci.sh." >&2
    exit 1
  fi
else
  printf '%s\n' "$generated" >.github/workflows/flutter-ci.yml
fi
