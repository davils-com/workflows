#!/usr/bin/env bash
# Builds a job matrix from the discovered packages.
#
# Each matrix entry is one job and carries the packages it works through, so the same workflow
# step serves every granularity:
#   package    one job per package (and SDK and operating system),
#   workspace  one job for all packages, like tool/verify.dart,
#   shards     the packages spread round-robin over SHARDS jobs,
#   auto       package up to SHARD_THRESHOLD packages, shards above.
#
# Environment:
#   DISCOVERY        output of discover.sh
#   AFFECTED         output of affected.sh (optional; without it every package is used)
#   TOOLCHAIN        dart, flutter or all
#   SELECT           all, tests (packages with a test/ directory), publishable, apps, executables,
#                    inspectra (packages with an Inspectra configuration or dependency)
#   SDKS             JSON array: stable, beta, lowest or a version (Flutter versions for flutter)
#   OS               JSON array: ubuntu, macos, windows, ubuntu-arm, windows-arm
#   EXTRA_OS_SDK     first (default): other operating systems only run the first SDK; all: every SDK
#   GRANULARITY      auto, package, workspace or shards
#   SHARDS           number of shards (default 8)
#   SHARD_THRESHOLD  package count from which auto shards (default 20)
#   RUNNERS          JSON object: linux, linux-arm, macos, windows, windows-arm runner labels
#   FLUTTER_RELEASES JSON array of stable Flutter releases ({version, dart}); with it, lowest is the
#                    oldest Flutter that satisfies environment.flutter and environment.sdk
#
# Prints {"include": [...], "count": n, "granularity": "...", "packages": [...every selected package...]}.
set -euo pipefail
# shellcheck source=../../_lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../_lib/common.sh"
require_commands jq

DISCOVERY="${DISCOVERY:?DISCOVERY is required}"
AFFECTED="${AFFECTED:-}"
[[ -z "$AFFECTED" ]] && AFFECTED="$(jq -c '{mode: "all", paths: [.packages[].path]}' <<<"$DISCOVERY")"

releases="${FLUTTER_RELEASES:-}"
[[ -z "$releases" ]] && releases='null'
runners="${RUNNERS:-}"
[[ -z "$runners" ]] && runners='{}'
sdks="${SDKS:-}"
[[ -z "$sdks" ]] && sdks='["stable"]'
os="${OS:-}"
[[ -z "$os" ]] && os='["ubuntu"]'

jq -cn \
  --argjson discovery "$DISCOVERY" \
  --argjson affected "$AFFECTED" \
  --arg toolchain "${TOOLCHAIN:-all}" \
  --arg select "${SELECT:-all}" \
  --argjson sdks "$sdks" \
  --argjson os "$os" \
  --arg extra_os_sdk "${EXTRA_OS_SDK:-first}" \
  --arg granularity "${GRANULARITY:-auto}" \
  --argjson shards "${SHARDS:-8}" \
  --argjson threshold "${SHARD_THRESHOLD:-20}" \
  --argjson runners "$runners" \
  --argjson releases "$releases" \
  '
  def semver_key: sub("[-+].*$"; "") | split(".") | map(tonumber? // 0);

  def runner($os):
    ({linux: "ubuntu-latest", "linux-arm": "ubuntu-24.04-arm", macos: "macos-latest", windows: "windows-latest", "windows-arm": "windows-11-arm"} + $runners) as $r
    | if $os == "ubuntu" then $r.linux
      elif $os == "ubuntu-arm" then $r["linux-arm"]
      elif $os == "macos" then $r.macos
      elif $os == "windows" then $r.windows
      elif $os == "windows-arm" then $r["windows-arm"]
      else $os end
    # A JSON array (self-hosted labels) arrives as a string; runs-on takes it as an array.
    | if type == "string" and startswith("[") then fromjson else . end;

  def version_for($sdk; $pkgs):
    if $sdk != "lowest" then $sdk
    elif $toolchain == "flutter" then
      ([$pkgs[].flutter_lower, $discovery.workspace.flutter_lower] | map(select(. != null)) | max_by(semver_key)) as $flutter
      | ([$pkgs[].sdk_lower, $discovery.workspace.sdk_lower] | map(select(. != null)) | max_by(semver_key)) as $dart
      # The oldest stable Flutter that satisfies both lower bounds: a Flutter version whose Dart is
      # older than the environment.sdk constraint cannot resolve the package.
      | if $releases == null or ($flutter == null and $dart == null) then $flutter
        else ([ $releases[]
                | select($flutter == null or (.version | semver_key) >= ($flutter | semver_key))
                | select($dart == null or (.dart | semver_key) >= ($dart | semver_key)) ]
              | sort_by(.version | semver_key) | first | .version) // $flutter
        end
    else
      ([$pkgs[].sdk_lower, $discovery.workspace.sdk_lower] | map(select(. != null)) | max_by(semver_key))
    end;

  [ $discovery.packages[]
    | select($toolchain == "all" or .toolchain == $toolchain)
    | select(.path as $p | $affected.paths | index($p))
    | select(
        if $select == "tests" then .has_tests
        elif $select == "publishable" then .publishable
        elif $select == "apps" then .app
        elif $select == "executables" then (.executables | length > 0)
        elif $select == "inspectra" then .inspectra
        else true end)
    | {name, path, workspace, type, toolchain, publishable, version, executables, platforms, has_tests, has_build_runner, has_l10n, has_integration_tests, inspectra, inspectra_dependency, internal_dependencies, sdk_lower, flutter_lower}
  ] as $pkgs
  | ($pkgs | length) as $n
  | (if $granularity == "auto" then (if $n > $threshold then "shards" else "package" end) else $granularity end) as $g
  | (if $n == 0 then []
     elif $g == "workspace" then [{id: "all", label: "all packages", packages: $pkgs}]
     elif $g == "shards" then
       ([$shards, $n] | min) as $k
       | [ range(0; $k) as $i
           | { id: ("shard-" + (($i + 1) | tostring)),
               label: ("shard " + (($i + 1) | tostring) + "/" + ($k | tostring)),
               packages: [ $pkgs | to_entries[] | select(.key % $k == $i) | .value ] } ]
     else [ $pkgs[] | {id: .name, label: .name, packages: [.]} ]
     end) as $groups
  | [ $groups[] as $group
      | ($os | to_entries[]) as $o
      | ($sdks | to_entries[]) as $s
      | select($o.key == 0 or $extra_os_sdk == "all" or $s.key == 0)
      | version_for($s.value; $group.packages) as $version
      | select($version != null)
      | {
          id: $group.id,
          label: ($group.label + " (" + $o.value + ", " + $s.value + (if $s.value == "lowest" then " " + $version else "" end) + ")"),
          packages: $group.packages,
          paths: ($group.packages | map(.path) | join(" ")),
          workspace: ($group.packages | any(.workspace)),
          os: $o.value,
          runner: runner($o.value),
          sdk: $version,
          sdk_label: $s.value,
          primary: ($o.key == 0 and $s.key == 0),
          first_os: ($o.key == 0)
        }
    ] as $include
  | {include: $include, count: ($include | length), granularity: $g, packages: $pkgs}
  '
