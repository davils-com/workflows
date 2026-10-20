#!/usr/bin/env bats
# Planning Flutter builds and native executables.

load helpers

plan() {
  run_script "$ACTIONS/plan-builds/scripts/plan.sh"
}

@test "web auto builds apps that have a web directory" {
  cd "$FIXTURES/dart-workspace"
  DISCOVERY="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")" KIND=flutter run plan
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.include[].id]' <<<"$output")" = '["davils_ci_demo-web"]' ]
  [ "$(jq -r '.include[0].workspace' <<<"$output")" = false ]
}

@test "a target without its platform directory is skipped" {
  cd "$FIXTURES/dart-workspace"
  DISCOVERY="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")" KIND=flutter TARGETS='{"web": false, "apk": true}' run --separate-stderr plan
  [ "$status" -eq 0 ]
  [ "$(jq -r '.count' <<<"$output")" = 0 ]
  [[ "$stderr" == *"no android/ directory"* ]]
}

@test "an unknown target is an error" {
  cd "$FIXTURES/dart-workspace"
  DISCOVERY="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")" KIND=flutter TARGETS='{"tvos": true}' run plan
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown Flutter build targets: tvos"* ]]
}

@test "every executable gets every target on its own runner" {
  cd "$FIXTURES/dart-single"
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" KIND=dart-compile TARGETS='["linux-arm64","macos-x64","windows-x64"]' run plan
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.include[] | [.id, .runner]]' <<<"$output")" = '[["single-linux-arm64","ubuntu-24.04-arm"],["single-macos-x64","macos-15-intel"],["single-windows-x64","windows-latest"]]' ]
  [ "$(jq -r '.include[0].entrypoint' <<<"$output")" = bin/single.dart ]
}

@test "explicit executables replace the pubspec ones" {
  cd "$FIXTURES/dart-single"
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" KIND=dart-compile TARGETS='["linux-x64"]' \
    EXECUTABLES='[{"package": "davils_ci_single", "entrypoint": "bin/single.dart", "name": "greet"}]' run plan
  [ "$(jq -c '[.include[].id]' <<<"$output")" = '["greet-linux-x64"]' ]
}
