#!/usr/bin/env bats
# Merging, validating and evaluating the configuration.

load helpers

merge() {
  run_script "$ACTIONS/resolve-config/scripts/merge.sh"
}

evaluate() {
  CONFIG="$1" DISCOVERY="$2" run_script "$ACTIONS/resolve-config/scripts/evaluate.sh"
}

@test "without any file the defaults apply" {
  cd "$BATS_TEST_TMPDIR"
  run merge
  [ "$status" -eq 0 ]
  [ "$(jq -c '.dart.sdks' <<<"$output")" = '["stable","lowest"]' ]
  [ "$(jq -r '.release.mode' <<<"$output")" = auto ]
}

@test "layers merge in order and lists replace" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .github
  printf 'version: 1\ndart:\n  sdks: [stable]\n  os: [ubuntu, macos]\n' >.github/davils-ci.yaml
  PRESET=cli CONFIG_INLINE='{"dart": {"os": ["windows"]}}' OVERRIDES='{"dart": {"enabled": false}}' run --separate-stderr merge
  [ "$status" -eq 0 ]
  [ "$(jq -c '.dart.sdks' <<<"$output")" = '["stable"]' ]
  [ "$(jq -c '.dart.os' <<<"$output")" = '["windows"]' ]
  [ "$(jq -r '.dart.enabled' <<<"$output")" = false ]
  [ "$(jq -r '.build["dart-compile"].enabled' <<<"$output")" = true ]
  [ "$(jq -r '.dart.format.enabled' <<<"$output")" = true ]
}

@test "an unknown option is an error" {
  cd "$BATS_TEST_TMPDIR"
  CONFIG_INLINE='dart: {formatt: {enabled: true}}' run merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"dart.formatt: unknown option"* ]]
}

@test "a value of the wrong type is an error" {
  cd "$BATS_TEST_TMPDIR"
  CONFIG_INLINE='dart: {sdks: stable}' run merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"dart.sdks: expected a list"* ]]
  CONFIG_INLINE='dart: {format: {enabled: maybe}}' run merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected true, false or auto"* ]]
}

@test "numbers given as strings become numbers" {
  cd "$BATS_TEST_TMPDIR"
  CONFIG_INLINE='{"timeouts": {"ci": "30"}, "writerside": {"builder-version": 2026}}' run merge
  [ "$status" -eq 0 ]
  [ "$(jq '.timeouts.ci' <<<"$output")" = 30 ]
  [ "$(jq '.writerside["builder-version"]' <<<"$output")" = '"2026"' ]
}

@test "an unknown preset is an error" {
  cd "$BATS_TEST_TMPDIR"
  PRESET=nope run merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"Known presets: cli,docs,flutter-app,library,workspace"* ]]
}

@test "a file of a later format version is an error" {
  cd "$BATS_TEST_TMPDIR"
  printf 'version: 2\n' >ci.yaml
  CONFIG_FILE=ci.yaml run merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"version 2"* ]]
}

@test "auto toggles follow the repository" {
  cd "$FIXTURES/dart-workspace"
  config="$(CONFIG_FILE=davils-ci.yaml merge)"
  discovery="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=push REF=refs/heads/main REF_NAME=main run evaluate "$config" "$discovery"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.run | to_entries | map(select(.value)) | map(.key)' <<<"$output")" = '["dart","flutter","dartdoc","pages","flutter-build"]' ]
  [ "$(jq -c '.config.build.flutter["resolved-targets"]' <<<"$output")" = '["web"]' ]
  [ "$(jq -r '.config.release.mode' <<<"$output")" = tag ]
}

@test "pull requests run the checks but deploy nothing" {
  cd "$FIXTURES/dart-workspace"
  config="$(merge)"
  discovery="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=pull_request REF=refs/pull/1/merge REF_NAME=1/merge BASE_REF=develop run evaluate "$config" "$discovery"
  [ "$(jq -c '.run | to_entries | map(select(.value)) | map(.key)' <<<"$output")" = '["pr-lint","dart","flutter","dartdoc"]' ]
}

@test "tags start the release when they match a pattern" {
  cd "$FIXTURES/dart-workspace"
  config="$(merge)"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=push REF=refs/tags/davils_ci_alpha-v1.2.0-beta.1 REF_NAME=davils_ci_alpha-v1.2.0-beta.1 run evaluate "$config" "$discovery"
  [ "$(jq -c '.event.tag' <<<"$output")" = '{"kind":"package","package":"davils_ci_alpha","version":"1.2.0-beta.1"}' ]
  [ "$(jq -c '.run | to_entries | map(select(.value)) | map(.key)' <<<"$output")" = '["release-tag"]' ]
  EVENT_NAME=push REF=refs/tags/random REF_NAME=random run evaluate "$config" "$discovery"
  [ "$(jq -c '.run | to_entries | map(select(.value)) | map(.key)' <<<"$output")" = '[]' ]
}

@test "path filters skip a feature when nothing relevant changed" {
  cd "$FIXTURES/dart-workspace"
  config="$(CONFIG_INLINE='dart: {when: {paths: ["packages/**"]}}' merge)"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  affected='{"mode":"all","base":"abc","changed_files":["README.md"],"paths":[]}'
  CONFIG="$config" DISCOVERY="$discovery" AFFECTED="$affected" EVENT_NAME=pull_request BASE_REF=main \
    run run_script "$ACTIONS/resolve-config/scripts/evaluate.sh"
  [ "$(jq -r '.run.dart' <<<"$output")" = false ]
  affected='{"mode":"all","base":"abc","changed_files":["packages/alpha/lib/a.dart"],"paths":[]}'
  CONFIG="$config" DISCOVERY="$discovery" AFFECTED="$affected" EVENT_NAME=pull_request BASE_REF=main \
    run run_script "$ACTIONS/resolve-config/scripts/evaluate.sh"
  [ "$(jq -r '.run.dart' <<<"$output")" = true ]
}

@test "branch filters apply to pushes" {
  cd "$FIXTURES/dart-workspace"
  config="$(merge)"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=push REF=refs/heads/develop REF_NAME=develop run evaluate "$config" "$discovery"
  [ "$(jq -r '.run.pages' <<<"$output")" = false ]
  [ "$(jq -r '.run.dart' <<<"$output")" = true ]
}

@test "release-please runs on pushes to the release branch when configured" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  echo '{}' >release-please-config.json
  config="$(merge)"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=push REF=refs/heads/main REF_NAME=main run evaluate "$config" "$discovery"
  [ "$(jq -r '.config.release.mode' <<<"$output")" = release-please ]
  [ "$(jq -r '.run["release-please"]' <<<"$output")" = true ]
  [ "$(jq -r '.run["dart-compile"]' <<<"$output")" = true ]
}

@test "Writerside instances are found from writerside.cfg" {
  dir="$(fixture_repo dart-single)"
  mkdir -p "$dir/docs"
  printf '<ihp version="2.0"><topics dir="topics"/><instance src="d.tree" version="1"/></ihp>\n' >"$dir/docs/writerside.cfg"
  printf '<instance-profile id="d" name="Docs" start-page="Home.md"></instance-profile>\n' >"$dir/docs/d.tree"
  cd "$dir"
  config="$(merge)"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=push REF=refs/heads/main REF_NAME=main run evaluate "$config" "$discovery"
  [ "$(jq -c '.config.writerside.instances' <<<"$output")" = '["docs/d"]' ]
  [ "$(jq -r '.run.writerside' <<<"$output")" = true ]
  [ "$(jq -r '.config.pages.parts.docs' <<<"$output")" = true ]
}

@test "every preset and the defaults satisfy the schema" {
  command -v check-jsonschema >/dev/null || skip "check-jsonschema is not installed"
  for preset in "$ACTIONS"/resolve-config/presets/*.yaml; do
    yq '.version = 1' "$preset" >"$BATS_TEST_TMPDIR/preset.yaml"
    check-jsonschema --schemafile "$REPO/schemas/davils-ci.schema.json" "$BATS_TEST_TMPDIR/preset.yaml"
  done
  yq '.version = 1' "$ACTIONS/resolve-config/defaults.yaml" >"$BATS_TEST_TMPDIR/defaults.yaml"
  check-jsonschema --schemafile "$REPO/schemas/davils-ci.schema.json" "$BATS_TEST_TMPDIR/defaults.yaml"
}

@test "on and off are toggles too" {
  cd "$FIXTURES/dart-workspace"
  config="$(OVERRIDES='{"dart": {"enabled": "off"}, "pr": {"title": {"enabled": "off"}, "branch-policy": {"enabled": "off"}}}' merge)"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  EVENT_NAME=pull_request BASE_REF=main run evaluate "$config" "$discovery"
  [ "$(jq -r '.run.dart' <<<"$output")" = false ]
  [ "$(jq -r '.run["pr-lint"]' <<<"$output")" = false ]
  [ "$(jq -r '.config.pr.title.enabled' <<<"$output")" = false ]
}
