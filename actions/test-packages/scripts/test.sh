#!/usr/bin/env bash
# Runs the tests of several packages one after the other and collects coverage and reports.
#
# A failing package does not stop the others; the script fails at the end and names every
# package that failed.
#
# Environment:
#   TOOL               dart or flutter
#   PACKAGES           JSON array of packages ({name, path, has_tests}), paths relative to the cwd
#   PLATFORMS          JSON array for dart test: vm, chrome, firefox, node, or <platform>:<compiler>
#                      such as chrome:dart2wasm; empty uses dart_test.yaml
#   COMMAND            replaces the test command; runs in the package directory with
#                      PACKAGE_NAME and PACKAGE_PATH set
#   ARGS               extra arguments for the test command
#   EXCLUDE_TAGS       tags to skip (flutter test --exclude-tags, dart test -x)
#   COVERAGE           true to write coverage/lcov.info per package
#   COVERAGE_SOURCE    auto, dart-ci, flutter-ci, inspectra or none
#   INSPECTRA_ENABLED  true when the inspectra workflow runs; with auto, packages whose Inspectra
#                      coverage gate is on leave coverage to it
#   REPORT             true to write a JSON test report per package
#   OUT_DIR            directory for the collected coverage (<name>.lcov) and reports (<name>.json)
#   REPO_PREFIX        the cwd relative to the repository root, for repository relative lcov paths
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

TOOL="${TOOL:-dart}"
PACKAGES="${PACKAGES:?PACKAGES is required}"
OUT_DIR="${OUT_DIR:-${RUNNER_TEMP:-/tmp}/davils-tests}"
mkdir -p "$OUT_DIR/coverage" "$OUT_DIR/reports"
prefix="${REPO_PREFIX:-.}"
prefix="${prefix#./}"
prefix="${prefix%/}"
[[ "$prefix" == . ]] && prefix=''
root="$(pwd -P)"

# Platform groups: platforms without a compiler run together, each platform:compiler on its own.
declare -a invocations=()
if [[ "$TOOL" == dart && -n "${PLATFORMS:-}" && "${PLATFORMS:-}" != '[]' ]]; then
  plain="$(jq -r '[.[] | select(contains(":") | not)] | join(",")' <<<"$PLATFORMS")"
  [[ -n "$plain" ]] && invocations+=("-p $plain")
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    invocations+=("-p ${item%%:*} -c ${item#*:}")
  done < <(jq -r '.[] | select(contains(":"))' <<<"$PLATFORMS")
else
  invocations+=("")
fi

supports_coverage_path() {
  dart test --help 2>/dev/null | grep -q -- '--coverage-path'
}

collect_lcov() {
  local name="$1" path="$2" file="$2/coverage/lcov.info"
  [[ -f "$file" ]] || {
    warn "$name wrote no coverage/lcov.info."
    return 0
  }
  local pkg_prefix
  if [[ "$path" == . ]]; then pkg_prefix="$prefix"; else pkg_prefix="${prefix:+$prefix/}$path"; fi
  # Source paths become relative to the repository root, whichever form the tool wrote.
  local abs_pkg
  abs_pkg="$(cd "$path" && pwd -P)"
  sed -E \
    -e "s#^SF:${abs_pkg}/#SF:${pkg_prefix:+$pkg_prefix/}#" \
    -e "s#^SF:${GITHUB_WORKSPACE:-/nonexistent}/##" \
    -e "s#^SF:(lib|bin|test)/#SF:${pkg_prefix:+$pkg_prefix/}\\1/#" \
    "$file" >"$OUT_DIR/coverage/$name.lcov"
}

failed=()
while IFS= read -r package; do
  name="$(jq -r '.name' <<<"$package")"
  path="$(jq -r '.path' <<<"$package")"
  if [[ "$(jq -r 'if has("has_tests") then .has_tests else true end' <<<"$package")" != true ]]; then
    echo "$name has no test directory; skipped."
    continue
  fi

  coverage="${COVERAGE:-false}"
  source_mode="${COVERAGE_SOURCE:-auto}"
  if [[ "$coverage" == true ]]; then
    case "$source_mode" in
      none | inspectra) coverage=false ;;
      auto)
        if [[ "${INSPECTRA_ENABLED:-false}" == true && "$(bash "$here/inspectra-coverage.sh" "$path")" == true ]]; then
          echo "Inspectra's coverage gate covers $name; its tests run there with coverage."
          coverage=false
        fi
        ;;
    esac
  fi

  echo "::group::Test $name ($path)"
  status=0
  # The subshell runs in an || list, where bash ignores set -e; every command that can fail
  # therefore exits the subshell with its status itself.
  (
    cd "$path" || exit 1
    export PACKAGE_NAME="$name" PACKAGE_PATH="$path"
    if [[ -n "${COMMAND:-}" ]]; then
      bash -euo pipefail -c "$COMMAND" || exit $?
      exit 0
    fi
    first=true
    for platform_args in "${invocations[@]}"; do
      args=()
      # shellcheck disable=SC2206
      [[ -n "$platform_args" ]] && args+=($platform_args)
      [[ -n "${EXCLUDE_TAGS:-}" ]] && args+=(--exclude-tags "$EXCLUDE_TAGS")
      if [[ "${REPORT:-false}" == true && "$first" == true ]]; then
        args+=(--file-reporter "json:$OUT_DIR/reports/$name.json")
      fi
      # shellcheck disable=SC2206
      [[ -n "${ARGS:-}" ]] && args+=($ARGS)
      if [[ "$TOOL" == flutter ]]; then
        [[ "$coverage" == true && "$first" == true ]] && args+=(--coverage)
        flutter test "${args[@]}" || exit $?
      elif [[ "$coverage" == true && "$first" == true ]]; then
        if supports_coverage_path; then
          dart test --coverage-path=coverage/lcov.info "${args[@]}" || exit $?
        else
          dart test --coverage=coverage/raw "${args[@]}" || exit $?
          dart pub global activate coverage >/dev/null || exit $?
          dart pub global run coverage:format_coverage --lcov --in=coverage/raw --out=coverage/lcov.info --report-on=lib --package=. || exit $?
        fi
      else
        dart test "${args[@]}" || exit $?
      fi
      first=false
    done
  ) || status=$?
  echo "::endgroup::"

  if ((status != 0)); then
    echo "::error title=Tests failed::$name ($path) failed with exit code $status."
    failed+=("$name")
  fi
  if [[ "$coverage" == true ]]; then
    collect_lcov "$name" "$path"
  fi
done < <(jq -c '.[]' <<<"$PACKAGES")

cd "$root"
if ((${#failed[@]} > 0)); then
  die "Tests failed in: ${failed[*]}."
fi
