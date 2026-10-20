#!/usr/bin/env bash
# Moves the pins Dependabot cannot see to their latest releases:
#
#   the Writerside builder image   Docker Hub tags of jetbrains/writerside-builder
#   actionlint, zizmor             GitHub releases, used by self-lint.yml
#   check-jsonschema               PyPI, used by self-lint.yml
#
# Prints a Markdown list of the changes; prints nothing when everything is current.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

auth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
changes=()

replace() {
  local old="$1" new="$2"
  shift 2
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    sed -i.bak "s#${old}#${new}#g" "$file"
    rm -f "$file.bak"
  done
}

# Writerside: the newest tag that looks like a builder version (2026.09.0357).
current_writerside="$(yq -r '.writerside["builder-version"]' actions/resolve-config/defaults.yaml)"
latest_writerside="$(curl -fsSL 'https://hub.docker.com/v2/repositories/jetbrains/writerside-builder/tags?page_size=50&ordering=last_updated' |
  jq -r '[.results[].name | select(test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$"))] | sort_by(split(".") | map(tonumber)) | last // empty')"
if [[ -n "$latest_writerside" && "$latest_writerside" != "$current_writerside" ]]; then
  replace "$current_writerside" "$latest_writerside" \
    actions/resolve-config/defaults.yaml actions/writerside-build/action.yml .github/workflows/writerside.yml
  changes+=("Writerside builder $current_writerside -> $latest_writerside")
fi

github_latest() {
  curl -fsSL "${auth[@]}" "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name | ltrimstr("v")'
}

for tool in actionlint:rhysd/actionlint zizmor:zizmorcore/zizmor; do
  name="${tool%%:*}"
  repo="${tool#*:}"
  variable="$(tr '[:lower:]' '[:upper:]' <<<"$name")_VERSION"
  current="$(sed -nE "s/^  ${variable}: '?([^' ]+)'?.*/\\1/p" .github/workflows/self-lint.yml)"
  latest="$(github_latest "$repo")"
  if [[ -n "$latest" && -n "$current" && "$latest" != "$current" ]]; then
    replace "${variable}: '${current}'" "${variable}: '${latest}'" .github/workflows/self-lint.yml
    changes+=("$name $current -> $latest")
  fi
done

current="$(sed -nE "s/^  CHECK_JSONSCHEMA_VERSION: '?([^' ]+)'?.*/\\1/p" .github/workflows/self-lint.yml)"
latest="$(curl -fsSL https://pypi.org/pypi/check-jsonschema/json | jq -r '.info.version')"
if [[ -n "$latest" && -n "$current" && "$latest" != "$current" ]]; then
  replace "CHECK_JSONSCHEMA_VERSION: '${current}'" "CHECK_JSONSCHEMA_VERSION: '${latest}'" .github/workflows/self-lint.yml
  changes+=("check-jsonschema $current -> $latest")
fi

if ((${#changes[@]} > 0)); then
  bash tools/gen-schema.sh
  printf -- '- %s\n' "${changes[@]}"
fi
