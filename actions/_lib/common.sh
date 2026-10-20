#!/usr/bin/env bash
# Shared helpers for the scripts of the composite actions. Sourced, never executed.
#
# Every script reads its inputs from environment variables, never from ${{ }} expressions, so a
# value from a pull request (a branch name, a title, a hook) can never become shell code.

# Prints an error annotation and exits.
die() {
  echo "::error::$*" >&2
  exit 1
}

warn() {
  echo "::warning::$*" >&2
}

notice() {
  echo "::notice::$*" >&2
}

# Writes a step output. Values with a newline use the heredoc form with a random delimiter.
set_output() {
  local name="$1" value="$2"
  local target="${GITHUB_OUTPUT:-/dev/stdout}"
  if [[ "$value" == *$'\n'* ]]; then
    local delimiter
    delimiter="davils_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    {
      echo "${name}<<${delimiter}"
      echo "$value"
      echo "$delimiter"
    } >>"$target"
  else
    echo "${name}=${value}" >>"$target"
  fi
}

# Exports an environment variable to the following steps.
set_env() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "${name}=${value}" >>"$GITHUB_ENV"
  fi
  export "${name}=${value}"
}

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$*" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# Splits a list given as newline, comma or JSON array into one item per line, without blanks.
split_list() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$raw" ]] && return 0
  if [[ "$raw" == \[* ]]; then
    jq -r '.[] | tostring' <<<"$raw"
  else
    printf '%s\n' "$raw" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
  fi
}

# Converts a list (see split_list) into a compact JSON array of strings.
list_to_json() {
  split_list "${1:-}" | jq -R . | jq -cs .
}

# Normalises a tri-state toggle to true, false or auto.
tri_state() {
  case "$(printf '%s' "${1:-auto}" | tr '[:upper:]' '[:lower:]')" in
    true | yes | on | 1) echo true ;;
    false | no | off | 0 | none) echo false ;;
    '' | auto) echo auto ;;
    *) die "'$1' is not a valid toggle; use true, false or auto." ;;
  esac
}

# Resolves a tri-state toggle against a detected value.
resolve_toggle() {
  local value detected="$2"
  value="$(tri_state "$1")"
  if [[ "$value" == auto ]]; then
    [[ "$detected" == true ]] && echo true || echo false
  else
    echo "$value"
  fi
}

# Matches a path against a glob with ** support (bash extglob and globstar semantics).
glob_match() {
  local path="$1" pattern="$2"
  # shellcheck disable=SC2053
  (
    shopt -s extglob globstar
    [[ "$path" == $pattern ]]
  )
}

# The lower bound of a version constraint: ^1.2.3 and >=1.2.3 <2.0.0 give 1.2.3, any gives nothing.
constraint_lower_bound() {
  local constraint="${1:-}"
  constraint="${constraint//\"/}"
  if [[ "$constraint" =~ ^\^([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$constraint" =~ \>=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$constraint" =~ ^([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Reads a YAML file as compact JSON; an empty or missing document gives {}.
yaml_to_json() {
  local file="$1"
  [[ -f "$file" ]] || {
    echo '{}'
    return 0
  }
  local json
  json="$(yq -o=json -I=0 '.' "$file")" || die "$file is not valid YAML."
  [[ -z "$json" || "$json" == null ]] && json='{}'
  echo "$json"
}

# Converts inline YAML or JSON text to compact JSON; empty text gives {}.
text_to_json() {
  local text="${1:-}"
  if [[ -z "${text//[[:space:]]/}" ]]; then
    echo '{}'
    return 0
  fi
  local json
  json="$(printf '%s' "$text" | yq -p=yaml -o=json -I=0 '.')" || die "The inline configuration is neither YAML nor JSON."
  [[ -z "$json" || "$json" == null ]] && json='{}'
  echo "$json"
}

# Deep-merges JSON objects given as arguments; later ones win, objects merge, arrays replace.
json_merge() {
  jq -cn --argjson n "$#" '
    def deepmerge($a; $b):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = deepmerge($a[$k]; $b[$k]))
      elif $b == null then $a
      else $b end;
    reduce $ARGS.positional[] as $x ({}; deepmerge(.; ($x | fromjson)))
  ' --args "$@"
}

# Requires the given commands to be installed.
require_commands() {
  local missing=()
  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  ((${#missing[@]} == 0)) || die "Missing required tools: ${missing[*]}."
}
