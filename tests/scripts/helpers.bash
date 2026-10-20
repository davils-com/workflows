# Shared setup of the bats tests: paths, a bash 4+ interpreter, temporary git repositories.
bats_require_minimum_version 1.5.0
REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ACTIONS="$REPO/actions"
FIXTURES="$REPO/tests/fixtures"
BASH_BIN="${BASH_BIN:-$(command -v bash)}"
if ((BASH_VERSINFO[0] < 4)) && [[ -x /opt/homebrew/bin/bash ]]; then
  BASH_BIN=/opt/homebrew/bin/bash
fi

run_script() {
  "$BASH_BIN" "$@"
}

# Copies a fixture into a fresh git repository and prints its path.
fixture_repo() {
  local name="$1" dir
  dir="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
  cp -R "$FIXTURES/$name/." "$dir/"
  (
    cd "$dir"
    git init -q -b main
    git -c user.email=ci@davils.test -c user.name=ci add -A
    git -c user.email=ci@davils.test -c user.name=ci commit -q -m init
  )
  echo "$dir"
}
