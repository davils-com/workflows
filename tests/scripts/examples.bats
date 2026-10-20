#!/usr/bin/env bats
# Every example configuration is valid and resolves to what its comments promise.

load helpers

# The preset an example's ci.yml passes, if any.
preset_of() {
  sed -nE 's/^ *preset: *([a-z-]+).*/\1/p' "$REPO/examples/$1/.github/workflows/ci.yml" | head -1
}

resolve() {
  local example="$1" fixture="$2" event="$3" ref="$4"
  cd "$FIXTURES/$fixture"
  local config discovery file=""
  [[ -f "$REPO/examples/$example/.github/davils-ci.yaml" ]] && file="$REPO/examples/$example/.github/davils-ci.yaml"
  config="$(PRESET="$(preset_of "$example")" CONFIG_FILE="${file:-none}" run_script "$ACTIONS/resolve-config/scripts/merge.sh" 2>/dev/null)"
  discovery="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh" 2>/dev/null)"
  CONFIG="$config" DISCOVERY="$discovery" EVENT_NAME="$event" REF="$ref" REF_NAME="${ref#refs/*/}" BASE_REF=main \
    run_script "$ACTIONS/resolve-config/scripts/evaluate.sh"
}

@test "every example configuration merges" {
  for dir in "$REPO"/examples/*/; do
    example="$(basename "$dir")"
    [[ -d "$dir/.github/workflows" ]] || continue
    run resolve "$example" dart-workspace push refs/heads/main
    [ "$status" -eq 0 ] || { echo "$example: $output"; false; }
  done
}

@test "the cli example compiles on main and releases on tags" {
  run resolve cli dart-single push refs/heads/main
  [ "$(jq -r '.run["dart-compile"]' <<<"$output")" = true ]
  [ "$(jq -c '.config.dart.os' <<<"$output")" = '["ubuntu","macos","windows"]' ]
  run resolve cli dart-single push refs/tags/v1.2.3
  [ "$(jq -c '.run | to_entries | map(select(.value)) | map(.key)' <<<"$output")" = '["release-tag"]' ]
}

@test "the flutter-app example builds every platform on main" {
  run resolve flutter-app dart-workspace push refs/heads/main
  [ "$(jq -r '.run["flutter-build"]' <<<"$output")" = true ]
  [ "$(jq -c '.config.build.flutter["resolved-targets"]' <<<"$output")" = '["web","apk","appbundle","ipa","macos","linux-x64","windows-x64"]' ]
  [ "$(jq -r '.config.pages.layout.web' <<<"$output")" = / ]
}

@test "the dart-workspace example checks only on pull requests and deploys on main" {
  run resolve dart-workspace dart-workspace pull_request refs/pull/1/merge
  [ "$(jq -r '.run.pages' <<<"$output")" = false ]
  [ "$(jq -r '.run["pr-lint"]' <<<"$output")" = true ]
  run resolve dart-workspace dart-workspace push refs/heads/main
  [ "$(jq -r '.run.pages' <<<"$output")" = true ]
  [ "$(jq -r '.config.pages.parts.coverage' <<<"$output")" = true ]
}

@test "the release-please example runs release-please on main" {
  # The example passes release: release-please to the pipeline, the topmost layer.
  OVERRIDES='{"release": {"mode": "release-please"}}' run resolve release-please dart-workspace push refs/heads/main
  [ "$(jq -r '.config.release.mode' <<<"$output")" = release-please ]
  [ "$(jq -r '.run["release-please"]' <<<"$output")" = true ]
}
