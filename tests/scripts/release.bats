#!/usr/bin/env bats
# Release tags, release notes and waiting for siblings on pub.dev.

load helpers

verify() {
  run_script "$ACTIONS/version-verify/scripts/verify.sh"
}

@test "a v tag of a single package is verified" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=v1.2.3 run verify
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.package, .path, .version, .kind, .prerelease]' <<<"$output")" = '["davils_ci_single",".","1.2.3","single",false]' ]
}

@test "a package tag of a workspace member is verified" {
  dir="$(fixture_repo dart-workspace)"
  cd "$dir"
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=refs/tags/davils_ci_alpha-v1.2.0 run verify
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.package, .path, .kind]' <<<"$output")" = '["davils_ci_alpha","packages/alpha","package"]' ]
}

@test "a version that differs from the pubspec is an error" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=v1.2.4 run verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"has version 1.2.3"* ]]
}

@test "an unknown package or pattern is an error" {
  dir="$(fixture_repo dart-workspace)"
  cd "$dir"
  discovery="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")"
  DISCOVERY="$discovery" TAG=nope-v1.0.0 run verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not have"* ]]
  DISCOVERY="$discovery" TAG=release-1 run verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"matches none"* ]]
}

@test "a pre-release with a build number in the pubspec is a pre-release" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  yq -i '.version = "2.0.0-beta.1+7"' pubspec.yaml
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=v2.0.0-beta.1 run verify
  [ "$status" -eq 0 ]
  [ "$(jq -r '.prerelease' <<<"$output")" = true ]
}

@test "custom tag patterns are honoured" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=1.2.3 TAG_PATTERNS='{"single": "{version}"}' run verify
  [ "$status" -eq 0 ]
  [ "$(jq -r '.version' <<<"$output")" = 1.2.3 ]
}

@test "a commit outside the release branch is an error" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  git clone -q --bare . "$BATS_TEST_TMPDIR/origin.git"
  git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git fetch -q origin
  git checkout -qb feature
  git -c user.email=ci@davils.test -c user.name=ci commit -q --allow-empty -m feature
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=v1.2.3 RELEASE_BRANCH=main run verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"not on main"* ]]
  git checkout -q main
  DISCOVERY="$(run_script "$ACTIONS/discover-packages/scripts/discover.sh")" TAG=v1.2.3 RELEASE_BRANCH=main run verify
  [ "$status" -eq 0 ]
}

@test "release notes come from the version's changelog section" {
  cd "$FIXTURES/dart-single"
  OUTPUT="$BATS_TEST_TMPDIR/notes.md" VERSION=1.2.3 SOURCE=auto run run_script "$ACTIONS/release-notes/scripts/notes.sh"
  [ "$status" -eq 0 ]
  [ "$output" = changelog ]
  grep -q 'The greeting.' "$BATS_TEST_TMPDIR/notes.md"
  ! grep -q '## \[1.2.3\]' "$BATS_TEST_TMPDIR/notes.md"
}

@test "without a changelog section the notes are generated, unless the changelog was asked for" {
  cd "$FIXTURES/dart-single"
  OUTPUT="$BATS_TEST_TMPDIR/notes.md" VERSION=9.9.9 SOURCE=auto run run_script "$ACTIONS/release-notes/scripts/notes.sh"
  [ "$output" = generate ]
  OUTPUT="$BATS_TEST_TMPDIR/notes.md" VERSION=9.9.9 SOURCE=changelog run run_script "$ACTIONS/release-notes/scripts/notes.sh"
  [ "$status" -ne 0 ]
}

@test "waiting for siblings asks pub.dev for their lowest version" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/curl" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >>"$CURL_LOG"
[[ "$*" == *"/api/packages/davils_ci_alpha/versions/1.2.0"* ]]
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cd "$FIXTURES/dart-workspace"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" PACKAGE_PATH=packages/nested/beta SIBLINGS='["davils_ci_alpha","davils_ci_beta"]' \
    ATTEMPTS=2 INTERVAL=0 run run_script "$ACTIONS/wait-for-pub-dev/scripts/wait.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"davils_ci_alpha 1.2.0 is on https://pub.dev"* ]]
}

@test "a sibling that never arrives fails the wait" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexit 22\n' >"$BATS_TEST_TMPDIR/bin/curl"
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  cd "$FIXTURES/dart-workspace"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" PACKAGE_PATH=packages/nested/beta SIBLINGS='["davils_ci_alpha"]' \
    ATTEMPTS=2 INTERVAL=0 run run_script "$ACTIONS/wait-for-pub-dev/scripts/wait.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not reach"* ]]
}

@test "tags are pushed three at a time" {
  dir="$(fixture_repo dart-single)"
  cd "$dir"
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  for n in 1 2 3 4 5 6 7; do git tag "pkg$n-v1.0.0"; done
  run "$BASH_BIN" "$REPO/tools/push-tags.sh" --pause 0
  [ "$status" -eq 0 ]
  [ "$(grep -c '^Pushing ' <<<"$output")" = 3 ]
  [ "$(git ls-remote --tags origin | wc -l | tr -d ' ')" = 7 ]
  run "$BASH_BIN" "$REPO/tools/push-tags.sh" --pause 0
  [[ "$output" == *"No tags to push."* ]]
}
