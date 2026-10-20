#!/usr/bin/env bats
# Job matrices from discovered packages.

load helpers

setup() {
  cd "$FIXTURES/dart-workspace"
  DISCOVERY="$(INCLUDE='apps/*' run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  export DISCOVERY
}

matrix() {
  run_script "$ACTIONS/build-matrix/scripts/matrix.sh"
}

@test "one job per package, SDK and operating system" {
  TOOLCHAIN=dart SELECT=tests SDKS='["stable","lowest"]' OS='["ubuntu","windows"]' run matrix
  [ "$status" -eq 0 ]
  [ "$(jq -r '.count' <<<"$output")" = 6 ]
  [ "$(jq -c '[.include[] | select(.primary) | .id]' <<<"$output")" = '["davils_ci_alpha","davils_ci_beta"]' ]
  [ "$(jq -c '[.include[] | .sdk] | unique' <<<"$output")" = '["3.13.5","stable"]' ]
  # Other operating systems only get the first SDK.
  [ "$(jq -c '[.include[] | select(.os == "windows") | .sdk]' <<<"$output")" = '["stable","stable"]' ]
}

@test "extra-os-sdk all gives every operating system every SDK" {
  TOOLCHAIN=dart SDKS='["stable","lowest"]' OS='["ubuntu","macos"]' EXTRA_OS_SDK=all run matrix
  [ "$(jq -r '.count' <<<"$output")" = 8 ]
}

@test "the workspace granularity makes one job" {
  TOOLCHAIN=dart GRANULARITY=workspace run matrix
  [ "$(jq -r '.count' <<<"$output")" = 1 ]
  [ "$(jq -r '.include[0].paths' <<<"$output")" = 'packages/alpha packages/nested/beta' ]
}

@test "shards spread the packages round-robin" {
  GRANULARITY=shards SHARDS=2 run matrix
  [ "$(jq -c '[.include[].paths]' <<<"$output")" = '["packages/alpha apps/demo_flutter","packages/nested/beta"]' ]
}

@test "auto shards above the threshold" {
  TOOLCHAIN=all SHARD_THRESHOLD=2 SHARDS=2 run matrix
  [ "$(jq -r '.granularity' <<<"$output")" = shards ]
  TOOLCHAIN=all SHARD_THRESHOLD=20 run matrix
  [ "$(jq -r '.granularity' <<<"$output")" = package ]
}

@test "the lowest Flutter version comes from environment.flutter" {
  TOOLCHAIN=flutter SDKS='["lowest"]' run matrix
  [ "$(jq -r '.include[0].sdk' <<<"$output")" = 3.38.0 ]
}

@test "only affected packages get jobs" {
  TOOLCHAIN=dart AFFECTED='{"mode":"affected","paths":["packages/nested/beta"]}' run matrix
  [ "$(jq -c '[.include[].id]' <<<"$output")" = '["davils_ci_beta"]' ]
}

@test "nothing to do gives an empty matrix" {
  TOOLCHAIN=dart AFFECTED='{"mode":"affected","paths":[]}' run matrix
  [ "$(jq -r '.count' <<<"$output")" = 0 ]
  [ "$(jq -c '.include' <<<"$output")" = '[]' ]
}

@test "self-hosted runner labels arrive as arrays" {
  TOOLCHAIN=dart RUNNERS='{"linux": "[\"self-hosted\",\"linux\"]"}' run matrix
  [ "$(jq -c '.include[0].runner' <<<"$output")" = '["self-hosted","linux"]' ]
  TOOLCHAIN=dart RUNNERS='{"linux": ["self-hosted","x64"]}' run matrix
  [ "$(jq -c '.include[0].runner' <<<"$output")" = '["self-hosted","x64"]' ]
}

@test "selections pick publishable packages and apps" {
  SELECT=publishable run matrix
  [ "$(jq -c '[.packages[].name]' <<<"$output")" = '["davils_ci_alpha"]' ]
  SELECT=apps run matrix
  [ "$(jq -c '[.packages[].name]' <<<"$output")" = '["davils_ci_demo"]' ]
}
