#!/usr/bin/env bash
# Resolves every auto toggle against the repository and decides which features run for this event.
#
# Environment:
#   CONFIG        merged configuration (merge.sh)
#   DISCOVERY     discovered packages (discover.sh)
#   AFFECTED      affected packages and changed files (affected.sh)
#   EVENT_NAME    github.event_name
#   REF           github.ref
#   REF_NAME      github.ref_name
#   BASE_REF      github.base_ref (pull requests) or the merge group base branch
#   IS_FORK       true when the pull request comes from a fork
#
# Prints {"config": {...resolved...}, "run": {...}, "event": {...}}.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"
require_commands jq
LIB_DIR="$(cd "$here/../../_lib" && pwd)"

CONFIG="${CONFIG:?CONFIG is required}"
DISCOVERY="${DISCOVERY:?DISCOVERY is required}"
AFFECTED="${AFFECTED:-}"
[[ -z "$AFFECTED" ]] && AFFECTED='{"mode":"all","changed_files":[],"paths":[]}'

event="${EVENT_NAME:-push}"
ref="${REF:-}"
if [[ "$event" == push && "$ref" == refs/tags/* ]]; then
  event=tag
fi
case "$event" in
  pull_request | pull_request_target | merge_group) branch="${BASE_REF:-}" ;;
  tag) branch='' ;;
  *) branch="${REF_NAME:-}" ;;
esac
branch="${branch#refs/heads/}"

# Writerside instances: <module dir>/<instance id> of every writerside.cfg below the working
# directory, read from the instance profiles of its trees.
instances='[]'
configured_instances="$(jq -c '.writerside.instances' <<<"$CONFIG")"
if [[ "$configured_instances" == '[]' ]]; then
  while IFS= read -r cfg; do
    [[ -z "$cfg" ]] && continue
    module="$(dirname "$cfg")"
    module="${module#./}"
    while IFS= read -r tree; do
      [[ -z "$tree" ]] && continue
      id="$(grep -o '<instance-profile[^>]*id="[^"]*"' "$module/$tree" 2>/dev/null | sed -E 's/.*id="([^"]*)".*/\1/' | head -1 || true)"
      [[ -z "$id" ]] && id="$(basename "$tree" .tree)"
      instances="$(jq -c --arg i "$module/$id" '. + [$i]' <<<"$instances")"
    done < <(grep -o '<instance[^-][^>]*src="[^"]*"' "$cfg" | sed -E 's/.*src="([^"]*)".*/\1/' || true)
  done < <(find . -name writerside.cfg -not -path './.davils-ci/*' -not -path '*/node_modules/*' -not -path '*/.dart_tool/*' -maxdepth 4 2>/dev/null | sort)
else
  instances="$configured_instances"
fi

release_please_config="$(jq -r '.release["release-please"]["config-file"]' <<<"$CONFIG")"
has_release_please=false
[[ -f "$release_please_config" ]] && has_release_please=true

jq -cn -L "$LIB_DIR" \
  --argjson config "$CONFIG" \
  --argjson discovery "$DISCOVERY" \
  --argjson affected "$AFFECTED" \
  --argjson instances "$instances" \
  --argjson has_release_please "$has_release_please" \
  --arg event "$event" \
  --arg raw_event "${EVENT_NAME:-push}" \
  --arg branch "$branch" \
  --arg ref_name "${REF_NAME:-}" \
  --arg is_fork "${IS_FORK:-false}" \
  '
  include "lib";
  $discovery.summary as $s
  | ($affected.changed_files // []) as $changed
  | ($affected.base // "" | length > 0) as $diff_known
  # Path globs are relative to the working directory, changed files to the repository root.
  | ($discovery.root | ltrimstr("./") | rtrimstr("/") | if . == "." then "" else . end) as $prefix
  | ($changed | map(if $prefix == "" then . elif startswith($prefix + "/") then ltrimstr($prefix + "/") else empty end)) as $relative

  | def when_ok($w):
      ($w.events | index($event)) != null
      and (($w.branches | length) == 0 or $branch == "" or ($branch | matches_any($w.branches)))
      and (($w.paths | length) == 0 or ($diff_known | not) or ($event | IN("pull_request", "merge_group", "push") | not)
           or ($relative | any(matches_any($w.paths))));

  # Which Flutter build targets an app would get; web auto means apps with a web directory.
    def flutter_targets:
      $config.build.flutter.targets | to_entries
      | map(.value |= tri)
      | map(select(.value == true or (.value == "auto" and .key == "web" and ($discovery.packages | any(.app and (.platforms | index("web") != null))))))
      | map(.key);

  # Enabled: the toggle resolved against what the repository has.
    ($config.dart.enabled | resolve($s.has_dart)) as $dart
  | ($config.flutter.enabled | resolve($s.has_flutter)) as $flutter
  | ($config.inspectra.enabled | resolve($s.has_inspectra)) as $inspectra
  | ($config.writerside.enabled | resolve($instances | length > 0)) as $writerside
  | ($config.dartdoc.enabled | resolve($s.has_publishable and $s.has_dart)) as $dartdoc
  | flutter_targets as $targets
  | ($config.build.flutter.enabled | resolve($s.has_apps and ($targets | length > 0))) as $flutter_build
  | ($config.build["dart-compile"].enabled | resolve($s.has_executables or ($config.build["dart-compile"].executables | length > 0))) as $dart_compile
  | ($config.release.mode | if . == "auto" then (if $has_release_please then "release-please" else "tag" end) else . end) as $release_mode
  | ($config.pages.parts | map_values(tri)) as $parts
  | ($dartdoc and ($parts.api != false)) as $api_part
  | ($writerside and ($parts.docs != false)) as $docs_part
  | ($flutter_build and ($targets | index("web") != null) and ($parts.web != false)) as $web_part
  | ($parts.coverage == true and ($dart or $flutter)) as $coverage_part
  | ($parts.inspectra == true and $inspectra) as $inspectra_part
  | ($config.pages.enabled | resolve($api_part or $docs_part or $web_part or $coverage_part or $inspectra_part)) as $pages

  # Tags: does the pushed tag match one of the release tag patterns?
  | (if $event == "tag" then parse_tag($ref_name; $config.release["tag-patterns"]) else null end) as $tag

  | (when_ok($config.dart.when)) as $dart_when
  | (when_ok($config.flutter.when)) as $flutter_when
  | {
      event: {name: $event, raw: $raw_event, branch: $branch, ref_name: $ref_name, fork: ($is_fork == "true"), tag: $tag},
      run: {
        "pr-lint": ((($config.pr.title.enabled | tri) != false or ($config.pr["branch-policy"].enabled | tri) != false) and when_ok($config.pr.when)),
        dart: ($dart and $dart_when),
        flutter: ($flutter and $flutter_when),
        inspectra: ($inspectra and when_ok($config.inspectra.when)),
        writerside: ($writerside and when_ok($config.writerside.when)),
        dartdoc: ($dartdoc and when_ok($config.dartdoc.when)),
        pages: ($pages and when_ok($config.pages.when)),
        "flutter-build": ($flutter_build and when_ok($config.build.flutter.when)),
        "dart-compile": ($dart_compile and when_ok($config.build["dart-compile"].when)),
        "release-tag": ($release_mode != "none" and $tag != null),
        "release-please": ($release_mode == "release-please" and $event == "push" and $branch == $config.project["release-branch"])
      },
      config: (
        $config
        | .dart.enabled = $dart
        | .flutter.enabled = $flutter
        | .inspectra.enabled = $inspectra
        | .writerside.enabled = $writerside
        | .writerside.instances = $instances
        | .dartdoc.enabled = $dartdoc
        | .pages.enabled = $pages
        | .pages.parts = {docs: $docs_part, api: $api_part, web: $web_part, coverage: $coverage_part, inspectra: $inspectra_part}
        | .build.flutter.enabled = $flutter_build
        | .build.flutter["resolved-targets"] = $targets
        | .build["dart-compile"].enabled = $dart_compile
        | .release.mode = $release_mode
        | .inspectra.check.root = (.inspectra.check.root | resolve($discovery.workspace.enabled))
        | .inspectra.sarif.enabled = (.inspectra.sarif.enabled | resolve($is_fork != "true"))
        | .inspectra["config-diff"].enabled = (.inspectra["config-diff"].enabled | resolve($event == "pull_request"))
        | .inspectra.report.enabled = (.inspectra.report.enabled | resolve($inspectra_part))
        | .dart["build-runner"].enabled = (.dart["build-runner"].enabled | resolve($s.has_build_runner))
        | .flutter["build-runner"].enabled = (.flutter["build-runner"].enabled | resolve($s.has_build_runner))
        | .dart["publish-dry-run"].enabled = (.dart["publish-dry-run"].enabled | resolve($s.has_publishable))
        | .flutter["publish-dry-run"].enabled = (.flutter["publish-dry-run"].enabled | resolve($s.has_publishable))
        | .flutter.l10n.enabled = (.flutter.l10n.enabled | resolve($discovery.packages | any(.has_l10n)))
        | .packages["affected-only"] = (.packages["affected-only"] | tri)
        | .security["harden-runner"].enabled = (.security["harden-runner"].enabled | resolve(true))
        # Every other toggle that is still auto or a string: on unless it says false, so typed
        # boolean inputs of the workflows receive true or false.
        | walk(if type == "object" and has("enabled") and ((.enabled | type) == "string") then .enabled |= resolve(true) else . end)
      )
    }
  '
