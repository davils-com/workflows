#!/usr/bin/env bats
# Package discovery and affected packages.

load helpers

@test "a single package is its own root" {
  cd "$FIXTURES/dart-single"
  run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.workspace.enabled' <<<"$output")" = false ]
  [ "$(jq -r '.packages | length' <<<"$output")" = 1 ]
  [ "$(jq -r '.packages[0].path' <<<"$output")" = . ]
  [ "$(jq -r '.packages[0].publishable' <<<"$output")" = true ]
  [ "$(jq -c '.packages[0].executables' <<<"$output")" = '[{"name":"single","entrypoint":"bin/single.dart"}]' ]
  [ "$(jq -r '.packages[0].sdk_lower' <<<"$output")" = 3.13.5 ]
}

@test "workspace members, nested ones and included packages are found" {
  cd "$FIXTURES/dart-workspace"
  INCLUDE='apps/*' run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.packages[].path]' <<<"$output")" = '["packages/alpha","packages/nested/beta","apps/demo_flutter"]' ]
  [ "$(jq -c '[.packages[].workspace]' <<<"$output")" = '[true,true,false]' ]
  [ "$(jq -c '[.packages[].toolchain]' <<<"$output")" = '["dart","dart","flutter"]' ]
  [ "$(jq -c '.packages[1].internal_dependencies' <<<"$output")" = '["davils_ci_alpha"]' ]
  [ "$(jq -r '.packages[2].app' <<<"$output")" = true ]
  [ "$(jq -r '.summary.has_flutter' <<<"$output")" = true ]
}

@test "excluded packages are left out" {
  cd "$FIXTURES/dart-workspace"
  INCLUDE='apps/*' EXCLUDE='packages/nested/**' run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.packages[].name]' <<<"$output")" = '["davils_ci_alpha","davils_ci_demo"]' ]
}

@test "a Flutter workspace member makes the workspace a Flutter workspace" {
  cd "$FIXTURES/flutter-workspace"
  run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.workspace.toolchain' <<<"$output")" = flutter ]
  [ "$(jq -c '[.packages[].toolchain] | unique' <<<"$output")" = '["flutter"]' ]
}

@test "a path dependency outside the repository is an error" {
  dir="$(fixture_repo dart-single)"
  yq -i '.dependencies.outside = {"path": "../../outside"}' "$dir/pubspec.yaml"
  cd "$dir"
  run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the repository"* ]]
  EXTERNAL_PATH_DEPS=warn run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -eq 0 ]
}

@test "a workspace member without resolution: workspace is an error" {
  dir="$(fixture_repo dart-workspace)"
  yq -i 'del(.resolution)' "$dir/packages/alpha/pubspec.yaml"
  cd "$dir"
  run run_script "$ACTIONS/discover-packages/scripts/discover.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"resolution: workspace"* ]]
}

@test "a change in a lower layer affects the packages depending on it" {
  dir="$(fixture_repo dart-workspace)"
  cd "$dir"
  base="$(git rev-parse HEAD)"
  echo '// change' >>packages/alpha/lib/davils_ci_alpha.dart
  git -c user.email=ci@davils.test -c user.name=ci commit -qam change
  discovery="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  DISCOVERY="$discovery" MODE=true BASE_SHA="$base" ALWAYS_ALL_PATHS='pubspec.yaml' run run_script "$ACTIONS/discover-packages/scripts/affected.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mode' <<<"$output")" = affected ]
  [ "$(jq -c '.paths' <<<"$output")" = '["packages/alpha","packages/nested/beta"]' ]
}

@test "a change in an upper layer only affects that package" {
  dir="$(fixture_repo dart-workspace)"
  cd "$dir"
  base="$(git rev-parse HEAD)"
  echo '// change' >>packages/nested/beta/lib/davils_ci_beta.dart
  git -c user.email=ci@davils.test -c user.name=ci commit -qam change
  discovery="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  DISCOVERY="$discovery" MODE=true BASE_SHA="$base" run run_script "$ACTIONS/discover-packages/scripts/affected.sh"
  [ "$(jq -c '.paths' <<<"$output")" = '["packages/nested/beta"]' ]
}

@test "a change to an always-all path affects every package" {
  dir="$(fixture_repo dart-workspace)"
  cd "$dir"
  base="$(git rev-parse HEAD)"
  echo '# change' >>pubspec.yaml
  git -c user.email=ci@davils.test -c user.name=ci commit -qam change
  discovery="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  DISCOVERY="$discovery" MODE=true BASE_SHA="$base" ALWAYS_ALL_PATHS='["pubspec.yaml"]' run run_script "$ACTIONS/discover-packages/scripts/affected.sh"
  [ "$(jq -r '.mode' <<<"$output")" = all ]
  [ "$(jq -c '.paths | length' <<<"$output")" = 3 ]
}

@test "outside pull requests every package is affected" {
  dir="$(fixture_repo dart-workspace)"
  cd "$dir"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  DISCOVERY="$discovery" MODE=auto EVENT_NAME=push BASE_SHA="$(git rev-parse HEAD)" run run_script "$ACTIONS/discover-packages/scripts/affected.sh"
  [ "$(jq -r '.mode' <<<"$output")" = all ]
}
