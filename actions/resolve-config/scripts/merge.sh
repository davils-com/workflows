#!/usr/bin/env bash
# Merges the configuration layers and checks the result against the defaults.
#
# Layers, lowest first: defaults.yaml, the preset, the configuration file, the inline configuration,
# the typed overrides. Mappings merge key by key, lists and scalars replace.
#
# Environment:
#   PRESET          library, workspace, flutter-app, cli, docs or empty
#   CONFIG_FILE     path relative to the current directory; empty means .github/davils-ci.yaml if it
#                   exists, none skips the file
#   CONFIG_INLINE   YAML or JSON text
#   OVERRIDES       JSON object built from the typed inputs of pipeline.yml
#   VALIDATE        true (default) or false
#
# Prints the merged configuration as compact JSON.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"
require_commands yq jq

action_dir="$here/.."
defaults="$(yaml_to_json "$action_dir/defaults.yaml")"

preset='{}'
if [[ -n "${PRESET:-}" ]]; then
  file="$action_dir/presets/${PRESET}.yaml"
  [[ -f "$file" ]] || die "Unknown preset '$PRESET'. Known presets: $(find "$action_dir/presets" -name '*.yaml' -exec basename {} .yaml \; | sort | paste -sd, -)."
  preset="$(yaml_to_json "$file")"
fi

file_json='{}'
config_file="${CONFIG_FILE:-}"
if [[ "$config_file" != none ]]; then
  if [[ -z "$config_file" ]]; then
    [[ -f .github/davils-ci.yaml ]] && config_file=.github/davils-ci.yaml
    [[ -z "$config_file" && -f .github/davils-ci.yml ]] && config_file=.github/davils-ci.yml
  elif [[ ! -f "$config_file" ]]; then
    die "The configuration file '$config_file' does not exist."
  fi
  if [[ -n "$config_file" ]]; then
    file_json="$(yaml_to_json "$config_file")"
    echo "Configuration file: $config_file" >&2
  fi
fi

inline="$(text_to_json "${CONFIG_INLINE:-}")"
overrides="${OVERRIDES:-}"
[[ -z "$overrides" ]] && overrides='{}'
jq -e 'type == "object"' <<<"$overrides" >/dev/null || die "OVERRIDES is not a JSON object."

for layer in "$preset" "$file_json" "$inline"; do
  jq -e 'type == "object"' <<<"$layer" >/dev/null || die "Every configuration layer has to be a mapping."
done

version="$(jq -r '.version // 1' <<<"$file_json")"
[[ "$version" == 1 ]] || die "$config_file has version $version; this release of davils-com/workflows reads version 1."

merged="$(json_merge "$defaults" "$preset" "$file_json" "$inline" "$overrides")"

if [[ "${VALIDATE:-true}" == true ]]; then
  # The defaults name every option, so an option missing from them is a typo. A value has to have
  # the type of its default; toggles also take auto, numbers given as strings are accepted.
  errors="$(jq -r --argjson d "$defaults" '
    def toggle_like: . == true or . == false or (type == "string" and (ascii_downcase | IN("auto", "true", "false", "on", "off", "yes", "no")));
    def walkcheck($d; $c; $p):
      if ($d | type) == "object" then
        if ($c | type) != "object" then "\($p): expected a mapping, found \($c | type)"
        else ($c | keys_unsorted[]) as $k
          | if ($d | has($k)) then walkcheck($d[$k]; $c[$k]; (if $p == "" then $k else "\($p).\($k)" end))
            elif ($p | test("(^|\\.)hooks$")) then empty
            else "\(if $p == "" then $k else "\($p).\($k)" end): unknown option" end
        end
      elif ($d | type) == "array" then
        if ($c | type) == "array" then empty else "\($p): expected a list, found \($c | type)" end
      elif ($d | type) == "boolean" or ($d == "auto") then
        if ($c | toggle_like) or (($d | type) == "string" and ($c | type) == "string") then empty
        else "\($p): expected true, false or auto, found \($c | tojson)" end
      elif ($d | type) == "number" then
        if ($c | type) == "number" or (($c | type) == "string" and ($c | test("^[0-9]+$"))) then empty
        else "\($p): expected a number, found \($c | tojson)" end
      elif ($d | type) == "string" then
        if ($c | type) == "string" or ($c | type) == "number" or ($c | type) == "boolean" then empty
        elif ($p | startswith("runners.")) and ($c | type) == "array" then empty
        else "\($p): expected a string, found \($c | type)" end
      else empty end;
    walkcheck($d; .; "")
  ' <<<"$merged")"
  if [[ -n "$errors" ]]; then
    while IFS= read -r line; do echo "::error title=davils-ci configuration::$line" >&2; done <<<"$errors"
    die "The configuration is invalid; see the errors above and schemas/davils-ci.schema.json."
  fi
fi

# Numbers given as strings become numbers, scalars given for strings become strings.
jq -c --argjson d "$defaults" '
  def coerce($d):
    if ($d | type) == "object" and type == "object" then with_entries(.key as $k | .value |= (if $d | has($k) then coerce($d[$k]) else . end))
    elif ($d | type) == "number" and type == "string" then tonumber
    elif ($d | type) == "string" and $d != "auto" and (type == "number" or type == "boolean") then tostring
    else . end;
  coerce($d)
' <<<"$merged"
