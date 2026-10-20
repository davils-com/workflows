#!/usr/bin/env bash
# Plans build jobs: Flutter app x target, or Dart executable x target, with the runner of each.
#
# Environment:
#   KIND         flutter or dart-compile
#   DISCOVERY    output of discover-packages
#   TARGETS      flutter: JSON object target -> true, false or auto (auto builds web for apps
#                with a web directory); dart-compile: JSON array of targets
#   APPS         flutter: JSON array of app package names; empty means every app
#   EXECUTABLES  dart-compile: JSON array of {package, entrypoint, name}; empty means every
#                executable of the pubspec.yaml files
#   RUNNERS      JSON object of runner labels
#
# Prints {"include": [...], "count": n}.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

DISCOVERY="${DISCOVERY:?DISCOVERY is required}"
runners="${RUNNERS:-}"
[[ -z "$runners" ]] && runners='{}'

case "${KIND:-flutter}" in
  flutter)
    targets="${TARGETS:-}"
    [[ -z "$targets" ]] && targets='{"web":"auto"}'
    apps="${APPS:-}"
    [[ -z "$apps" ]] && apps='[]'
    jq -cn -L "$here/../../_lib" --argjson d "$DISCOVERY" --argjson targets "$targets" --argjson apps "$apps" --argjson runners "$runners" '
      include "lib";
      ({linux: "ubuntu-latest", "linux-arm": "ubuntu-24.04-arm", macos: "macos-latest", windows: "windows-latest", "windows-arm": "windows-11-arm"} + $runners) as $r
      | def fix: if type == "string" and startswith("[") then fromjson else . end;
        {
          web:           {platform: "web",     runner: $r.linux},
          apk:           {platform: "android", runner: $r.linux},
          appbundle:     {platform: "android", runner: $r.linux},
          ios:           {platform: "ios",     runner: $r.macos},
          ipa:           {platform: "ios",     runner: $r.macos},
          macos:         {platform: "macos",   runner: $r.macos},
          "linux-x64":   {platform: "linux",   runner: $r.linux},
          "linux-arm64": {platform: "linux",   runner: $r["linux-arm"]},
          "windows-x64": {platform: "windows", runner: $r.windows},
          "windows-arm64": {platform: "windows", runner: $r["windows-arm"]}
        } as $known
      | ($targets | keys - ($known | keys)) as $unknown
      | if ($unknown | length) > 0 then error("Unknown Flutter build targets: \($unknown | join(", ")).") else . end
      | [ $d.packages[]
          | select(.app or (($apps | length) > 0 and (.name as $n | $apps | index($n))))
          | select(($apps | length) == 0 or (.name as $n | $apps | index($n)))
          | . as $app
          | $targets | to_entries[]
          | (.value | tri) as $t
          | select($t == true or ($t == "auto" and .key == "web" and ($app.platforms | index("web"))))
          | .key as $target
          | $known[$target] as $k
          | if ($app.platforms | index($k.platform)) == null then
              ("\($app.name) has no \($k.platform)/ directory; the \($target) build is skipped.\n" | stderr | empty)
            else
              {id: "\($app.name)-\($target)", label: "\($app.name) \($target)", app: $app.name, path: $app.path,
               target: $target, platform: $k.platform, runner: ($k.runner | fix), version: $app.version, workspace: $app.workspace}
            end
        ] as $include
      | {include: $include, count: ($include | length)}
    '
    ;;
  dart-compile)
    targets="${TARGETS:-}"
    [[ -z "$targets" ]] && targets='["linux-x64","linux-arm64","macos-arm64","macos-x64","windows-x64"]'
    executables="${EXECUTABLES:-}"
    [[ -z "$executables" ]] && executables='[]'
    jq -cn --argjson d "$DISCOVERY" --argjson targets "$targets" --argjson executables "$executables" --argjson runners "$runners" '
      ({linux: "ubuntu-latest", "linux-arm": "ubuntu-24.04-arm", macos: "macos-latest", "macos-intel": "macos-15-intel", windows: "windows-latest", "windows-arm": "windows-11-arm"} + $runners) as $r
      | def fix: if type == "string" and startswith("[") then fromjson else . end;
        {
          "linux-x64": $r.linux, "linux-arm64": $r["linux-arm"],
          "macos-arm64": $r.macos, "macos-x64": $r["macos-intel"],
          "windows-x64": $r.windows, "windows-arm64": $r["windows-arm"]
        } as $known
      | ($targets - ($known | keys)) as $unknown
      | if ($unknown | length) > 0 then error("Unknown compile targets: \($unknown | join(", ")).") else . end
      | (if ($executables | length) > 0 then
           [ $executables[] as $e
             | ($d.packages[] | select(.name == $e.package)) as $p
             | {package: $p.name, path: $p.path, version: $p.version, workspace: $p.workspace, entrypoint: $e.entrypoint, name: ($e.name // ($e.entrypoint | split("/") | last | rtrimstr(".dart")))} ]
         else
           [ $d.packages[] as $p | $p.executables[] | {package: $p.name, path: $p.path, version: $p.version, workspace: $p.workspace, entrypoint, name} ]
         end) as $exes
      | [ $exes[] as $e | $targets[] as $t
          | {id: "\($e.name)-\($t)", label: "\($e.name) \($t)", target: $t, runner: ($known[$t] | fix)} + $e ] as $include
      | {include: $include, count: ($include | length)}
    '
    ;;
  *) die "Unknown KIND '${KIND:-}'." ;;
esac
