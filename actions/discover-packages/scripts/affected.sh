#!/usr/bin/env bash
# Narrows the discovered packages to the ones a change affects, and lists the changed files.
#
# A package is affected when a changed file lies inside it, or when it depends (also as a dev
# dependency) on an affected package of the repository. A change to one of ALWAYS_ALL_PATHS (the
# workspace pubspec.yaml, analysis_options.yaml, inspectra.base.yaml, ...) affects every package.
#
# Environment:
#   DISCOVERY          output of discover.sh
#   MODE               true, false or auto (auto: on pull_request and merge_group events)
#   EVENT_NAME         github.event_name
#   BASE_SHA           the commit to compare with: the pull request base, the merge group base or
#                      the commit before a push; empty or all zeros means every package
#   ALWAYS_ALL_PATHS   globs relative to the working directory
#   ROOT               the working directory, relative to the repository root
#
# Prints {"mode": "all"|"affected", "base": "...", "changed_files": [...], "paths": [...]}.
set -euo pipefail
# shellcheck source=../../_lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../_lib/common.sh"
require_commands jq git
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)"

DISCOVERY="${DISCOVERY:?DISCOVERY is required}"
ROOT="${ROOT:-.}"
all_paths="$(jq -c '[.packages[].path]' <<<"$DISCOVERY")"

emit() {
  jq -cn --arg mode "$1" --arg base "${BASE_SHA:-}" --argjson changed "$2" --argjson paths "$3" \
    '{mode: $mode, base: $base, changed_files: $changed, paths: $paths}'
}

mode="$(tri_state "${MODE:-auto}")"
if [[ "$mode" == auto ]]; then
  case "${EVENT_NAME:-}" in
    pull_request | pull_request_target | merge_group) mode=true ;;
    *) mode=false ;;
  esac
fi

base="${BASE_SHA:-}"
changed='[]'
if [[ -n "$base" && ! "$base" =~ ^0+$ ]]; then
  if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    # The checkout keeps no credentials; a private repository needs the token for this fetch.
    auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')")
    fi
    git "${auth[@]}" fetch --no-tags --quiet --depth=1 origin "$base" 2>/dev/null || true
  fi
  if git cat-file -e "${base}^{commit}" 2>/dev/null; then
    # Two dots on purpose: for a pull request HEAD is the merge commit whose first parent is the
    # base, for a push the base is the commit before it; both give exactly the change.
    changed="$(git diff --name-only "$base" HEAD | jq -R . | jq -cs .)"
  else
    warn "The base commit $base is not available; every package counts as affected."
    base=''
  fi
else
  base=''
fi

if [[ "$mode" != true || -z "$base" ]]; then
  emit all "$changed" "$all_paths"
  exit 0
fi

# Changed files relative to the working directory; files outside it are dropped.
prefix="${ROOT#./}"
prefix="${prefix%/}"
[[ "$prefix" == . ]] && prefix=''
relative="$(jq -c --arg prefix "$prefix" '
  map(if $prefix == "" then . elif startswith($prefix + "/") then ltrimstr($prefix + "/") else empty end)
' <<<"$changed")"

always="$(list_to_json "${ALWAYS_ALL_PATHS:-}")"
if jq -e -L "$LIB_DIR" --argjson globs "$always" 'include "lib"; any(.[]; matches_any($globs))' <<<"$relative" >/dev/null; then
  emit all "$changed" "$all_paths"
  exit 0
fi

paths="$(jq -c --argjson files "$relative" '
  .packages as $packages
  # Every changed file belongs to the package with the longest path that contains it.
  | [ $files[] as $f
      | [ $packages[] | select(.path as $p | $p == "." or ($f | startswith($p + "/"))) ]
      | sort_by(.path | length) | last | select(. != null) | .name ] | unique as $direct
  # Then everything that depends on an affected package, until nothing changes.
  | { set: $direct, done: false }
  | until(.done;
      .set as $s
      | ([ $packages[] | select((.internal_dependencies + .internal_dev_dependencies) | any(. as $d | $s | index($d))) | .name ] + $s | unique) as $next
      | { set: $next, done: ($next == $s) })
  | .set as $names
  | [ $packages[] | select(.name as $n | $names | index($n)) | .path ]
' <<<"$DISCOVERY")"

emit affected "$changed" "$paths"
