#!/usr/bin/env bash
# Finds every Dart and Flutter package of a repository and prints them as JSON.
#
# Sources, in this order:
#   1. the root pubspec.yaml; with a `workspace:` list its members (paths or globs), otherwise the
#      root package itself,
#   2. the INCLUDE globs, for packages outside the workspace (a Flutter app next to a pure Dart
#      workspace, for example).
# EXCLUDE globs remove packages from both. Paths in the output are relative to ROOT.
#
# Environment:
#   ROOT                 directory of the root pubspec.yaml (default: .)
#   INCLUDE / EXCLUDE    globs, newline or comma separated, or a JSON array
#   EXTERNAL_PATH_DEPS   error (default) or warn, for path dependencies that leave the repository
set -euo pipefail
# shellcheck source=../../_lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../_lib/common.sh"
require_commands yq jq
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)"

ROOT="${ROOT:-.}"
[[ -d "$ROOT" ]] || die "The working directory '$ROOT' does not exist."
cd "$ROOT"
repo_top="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

shopt -s globstar nullglob extglob

default_excludes=('**/.dart_tool/**' '**/build/**' '.davils-ci/**' '**/.symlinks/**' '**/ephemeral/**')
mapfile -t excludes < <(split_list "${EXCLUDE:-}")
mapfile -t includes < <(split_list "${INCLUDE:-}")

normalize() {
  local path="${1#./}"
  path="${path%/}"
  [[ -z "$path" ]] && path=.
  echo "$path"
}

is_excluded() {
  local path="$1" pattern
  for pattern in "${default_excludes[@]}" "${excludes[@]}"; do
    [[ -z "$pattern" ]] && continue
    pattern="${pattern#./}"
    pattern="${pattern%/}"
    if glob_match "$path" "$pattern" || glob_match "$path/" "$pattern"; then
      return 0
    fi
  done
  return 1
}

[[ -f pubspec.yaml ]] || die "No pubspec.yaml in '$ROOT'. Set working-directory to the directory of the root pubspec.yaml."
root_json="$(yaml_to_json pubspec.yaml)"

declare -a candidates=()
declare -a members=()
workspace_enabled=false
if jq -e '(.workspace // null) | type == "array"' <<<"$root_json" >/dev/null; then
  workspace_enabled=true
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    matched=false
    # A workspace entry may be a glob since Dart 3.11; expanding a plain path just returns it.
    for dir in $entry; do
      if [[ -f "$dir/pubspec.yaml" ]]; then
        candidates+=("$(normalize "$dir")")
        members+=("$(normalize "$dir")")
        matched=true
      fi
    done
    [[ "$matched" == true ]] || die "The workspace entry '$entry' of pubspec.yaml matches no directory with a pubspec.yaml."
  done < <(jq -r '.workspace[]' <<<"$root_json")
else
  candidates+=(.)
fi

for pattern in "${includes[@]}"; do
  pattern="${pattern#./}"
  pattern="${pattern%/}"
  matched=false
  for dir in $pattern; do
    if [[ -d "$dir" && -f "$dir/pubspec.yaml" ]]; then
      candidates+=("$(normalize "$dir")")
      matched=true
    fi
  done
  [[ "$matched" == true ]] || warn "The include glob '$pattern' matches no directory with a pubspec.yaml."
done

# Every package once, in a stable order.
mapfile -t candidates < <(printf '%s\n' "${candidates[@]}" | awk '!seen[$0]++')

packages='[]'
for path in "${candidates[@]}"; do
  if [[ "$path" != . ]] && is_excluded "$path"; then
    continue
  fi
  json="$(yaml_to_json "$path/pubspec.yaml")"
  name="$(jq -r '.name // empty' <<<"$json")"
  [[ -n "$name" ]] || die "$path/pubspec.yaml has no name."

  in_workspace=false
  if [[ "$workspace_enabled" == true ]] && printf '%s\n' "${members[@]}" | grep -qxF -- "$path"; then
    jq -e '.resolution == "workspace"' <<<"$json" >/dev/null ||
      die "$path is listed in the workspace of pubspec.yaml but its pubspec.yaml lacks 'resolution: workspace'."
    in_workspace=true
  fi

  # A package path dependency that leaves the repository cannot resolve on a runner.
  while IFS= read -r dep_path; do
    [[ -z "$dep_path" ]] && continue
    target="$(cd "$path" && cd "$dep_path" 2>/dev/null && pwd -P || true)"
    if [[ -z "$target" || "$target" != "$repo_top"* ]]; then
      message="$path/pubspec.yaml depends on '$dep_path' by path, outside the repository. The reusable workflows only check out this repository; publish that dependency or use a git dependency."
      if [[ "${EXTERNAL_PATH_DEPS:-error}" == warn ]]; then warn "$message"; else die "$message"; fi
    fi
  done < <(jq -r '[.dependencies, .dev_dependencies, .dependency_overrides] | map(select(. != null) | to_entries[] | .value | select(type == "object" and has("path")) | .path) | .[]' <<<"$json")

  platforms='[]'
  for platform in android ios linux macos windows web; do
    [[ -d "$path/$platform" ]] && platforms="$(jq -c --arg p "$platform" '. + [$p]' <<<"$platforms")"
  done

  has_inspectra_file=false
  for file in "$path"/inspectra.yaml "$path"/inspectra.yml; do
    [[ -f "$file" ]] && has_inspectra_file=true
  done

  package="$(jq -c -L "$LIB_DIR" \
    --arg path "$path" \
    --argjson workspace "$in_workspace" \
    --argjson platforms "$platforms" \
    --argjson has_tests "$([[ -d "$path/test" ]] && echo true || echo false)" \
    --argjson has_integration_tests "$([[ -d "$path/integration_test" ]] && echo true || echo false)" \
    --argjson has_main "$([[ -f "$path/lib/main.dart" ]] && echo true || echo false)" \
    --argjson has_l10n "$([[ -f "$path/l10n.yaml" ]] && echo true || echo false)" \
    --argjson has_inspectra_file "$has_inspectra_file" \
    '
    include "lib";
    (.dependencies.flutter.sdk == "flutter") as $flutter
    | (((.publish_to // "") | tostring) != "none") as $publishable
    | (has_dep(.dependencies; "inspectra") or has_dep(.dev_dependencies; "inspectra")) as $inspectra_dep
    | {
        name: .name,
        path: $path,
        version: ((.version // "") | tostring),
        type: (if $flutter then "flutter" else "dart" end),
        workspace: $workspace,
        publishable: $publishable,
        app: ($flutter and ($publishable | not) and ($platforms | length > 0) and $has_main),
        platforms: $platforms,
        has_tests: $has_tests,
        has_integration_tests: $has_integration_tests,
        has_build_runner: (has_dep(.dev_dependencies; "build_runner") or has_dep(.dependencies; "build_runner")),
        has_l10n: ($has_l10n or (.flutter.generate == true)),
        inspectra: ($inspectra_dep or has("inspectra") or $has_inspectra_file),
        inspectra_dependency: $inspectra_dep,
        executables: ((.executables // {}) | to_entries | map({name: .key, entrypoint: ("bin/" + ((.value // .key) | tostring) + ".dart")})),
        sdk_lower: lower_bound(.environment.sdk),
        flutter_lower: lower_bound(.environment.flutter),
        dependencies: dep_names(.dependencies),
        dev_dependencies: dep_names(.dev_dependencies)
      }
    ' <<<"$json")"
  packages="$(jq -c --argjson p "$package" '. + [$p]' <<<"$packages")"
done

# Duplicate package names make tags and pub.dev ambiguous.
duplicates="$(jq -r 'group_by(.name) | map(select(length > 1) | .[0].name) | join(", ")' <<<"$packages")"
[[ -z "$duplicates" ]] || die "Several packages share a name: $duplicates."

# Internal dependencies, the toolchain and the release tag prefix of every package.
workspace_has_flutter="$(jq '[.[] | select(.workspace and .type == "flutter")] | length > 0' <<<"$packages")"
root_type="$(jq -r 'if .dependencies.flutter.sdk == "flutter" then "flutter" else "dart" end' <<<"$root_json")"
[[ "$root_type" == flutter && "$workspace_enabled" == true ]] && workspace_has_flutter=true

packages="$(jq -c --argjson wsflutter "$workspace_has_flutter" '
  (map(.name)) as $names
  | map(
      . as $p
      | .internal_dependencies = ([.dependencies[] | select(. as $d | $names | index($d))] | unique)
      | .internal_dev_dependencies = ([.dev_dependencies[] | select(. as $d | $names | index($d))] | unique)
      | .toolchain = (if .workspace and $wsflutter then "flutter" else .type end)
      | del(.dependencies, .dev_dependencies)
    )
' <<<"$packages")"

root_inspectra="$(jq -L "$LIB_DIR" 'include "lib"; has_dep(.dev_dependencies; "inspectra") or has_dep(.dependencies; "inspectra") or has("inspectra")' <<<"$root_json")"
for file in inspectra.yaml inspectra.yml inspectra.base.yaml; do
  [[ -f "$file" ]] && root_inspectra=true
done

jq -cn -L "$LIB_DIR" \
  --argjson packages "$packages" \
  --argjson workspace_enabled "$workspace_enabled" \
  --argjson root "$root_json" \
  --argjson wsflutter "$workspace_has_flutter" \
  --argjson root_inspectra "$root_inspectra" \
  --arg root_path "$ROOT" \
  '
  include "lib";
  {
    root: $root_path,
    workspace: {
      enabled: $workspace_enabled,
      name: ($root.name // ""),
      toolchain: (if $wsflutter then "flutter" else "dart" end),
      sdk_lower: lower_bound($root.environment.sdk),
      flutter_lower: lower_bound($root.environment.flutter),
      inspectra: $root_inspectra,
      inspectra_dependency: (has_dep($root.dependencies; "inspectra") or has_dep($root.dev_dependencies; "inspectra"))
    },
    packages: $packages,
    summary: {
      count: ($packages | length),
      has_dart: ($packages | any(.toolchain == "dart")),
      has_flutter: ($packages | any(.toolchain == "flutter")),
      has_publishable: ($packages | any(.publishable)),
      has_apps: ($packages | any(.app)),
      has_executables: ($packages | any(.executables | length > 0)),
      has_inspectra: ($root_inspectra or ($packages | any(.inspectra))),
      has_build_runner: ($packages | any(.has_build_runner))
    }
  }
  '
