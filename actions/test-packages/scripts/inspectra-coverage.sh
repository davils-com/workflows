#!/usr/bin/env bash
# Prints true when Inspectra's coverage gate is on for a package, false otherwise.
#
# The gate runs the tests itself (dart test --coverage), so dart-ci and flutter-ci leave the
# coverage of such a package to the inspectra workflow instead of running the tests twice.
# The configuration is the inspectra.yaml next to the pubspec.yaml, or else the inspectra: section
# of the pubspec.yaml; relative `extends` bases are followed, the nearest layer wins.
#
# Usage: inspectra-coverage.sh <package directory>
set -euo pipefail
dir="${1:?package directory}"

layer_value() {
  # Prints the coverage.enabled value of a layer and the extends paths, one per line, as
  # "enabled <value>" and "extends <path>".
  local file="$1" section="$2"
  yq -r "${section}.coverage.enabled // \"\" | \"enabled \" + tostring" "$file" 2>/dev/null || true
  yq -r "(${section}.extends // []) | (select(type == \"!!str\") | [.]) // . | .[] | select(type == \"!!str\") | \"extends \" + ." "$file" 2>/dev/null || true
}

resolve() {
  local file="$1" section="$2" depth="${3:-0}"
  ((depth > 8)) && return 0
  local enabled='' line base
  while IFS= read -r line; do
    case "$line" in
      'enabled true' | 'enabled false') enabled="${line#enabled }" ;;
      extends\ *)
        base="${line#extends }"
        [[ "$base" == package:* || "$base" == http* ]] && continue
        base="$(dirname "$file")/$base"
        if [[ -z "$enabled" && -f "$base" ]]; then
          enabled="$(resolve "$base" '' $((depth + 1)))"
        fi
        ;;
    esac
  done < <(layer_value "$file" "$section")
  echo "$enabled"
}

if [[ -f "$dir/inspectra.yaml" ]]; then
  result="$(resolve "$dir/inspectra.yaml" '')"
elif [[ -f "$dir/inspectra.yml" ]]; then
  result="$(resolve "$dir/inspectra.yml" '')"
elif [[ -f "$dir/pubspec.yaml" ]] && [[ "$(yq -r 'has("inspectra")' "$dir/pubspec.yaml")" == true ]]; then
  result="$(resolve "$dir/pubspec.yaml" '.inspectra')"
else
  result=''
fi
[[ "$result" == true ]] && echo true || echo false
