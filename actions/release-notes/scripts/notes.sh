#!/usr/bin/env bash
# Writes the release notes of a version to a file.
#
#   inspectra  inspectra changelog notes <version> (the Inspectra changelog configuration applies)
#   changelog  the section of the version in the package's CHANGELOG.md (Keep a Changelog:
#              "## [1.2.3] - date" or "## 1.2.3")
#   file       a file of the repository
#   generate   nothing here; GitHub generates the notes from the pull requests
#   auto       inspectra when INSPECTRA is set and the package has an Inspectra configuration,
#              otherwise changelog when the section exists, otherwise generate
#
# Environment:
#   SOURCE         auto, inspectra, changelog, file or generate
#   PACKAGE_PATH   directory of the package
#   VERSION        the released version
#   NOTES_FILE     for file: the path, relative to the current directory
#   INSPECTRA      the command that runs Inspectra (for inspectra and auto)
#   HAS_INSPECTRA  true when the package has an Inspectra configuration
#   OUTPUT         the file to write
#
# Prints the source that was used: inspectra, changelog, file or generate.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

source_mode="${SOURCE:-auto}"
path="${PACKAGE_PATH:-.}"
version="${VERSION:?VERSION is required}"
output="${OUTPUT:?OUTPUT is required}"

changelog_section() {
  local file="$path/CHANGELOG.md"
  [[ -f "$file" ]] || return 1
  # From the heading of the version to the next heading of the same level.
  awk -v v="$version" '
    BEGIN { found = 0 }
    /^## / {
      if (found) exit
      line = $0
      gsub(/[\[\]]/, "", line)
      split(line, parts, /[ \t]+/)
      if (parts[2] == v || parts[2] == "v" v) { found = 1; next }
    }
    found { print }
  ' "$file" | sed -e '/./,$!d' >"$output.tmp"
  if [[ -s "$output.tmp" ]]; then
    mv "$output.tmp" "$output"
    return 0
  fi
  rm -f "$output.tmp"
  return 1
}

if [[ "$source_mode" == auto ]]; then
  if [[ -n "${INSPECTRA:-}" && "${HAS_INSPECTRA:-false}" == true ]]; then
    source_mode=inspectra
  elif changelog_section; then
    echo changelog
    exit 0
  else
    source_mode=generate
  fi
fi

case "$source_mode" in
  inspectra)
    [[ -n "${INSPECTRA:-}" ]] || die "notes-source inspectra needs Inspectra."
    read -r -a command <<<"$INSPECTRA"
    "${command[@]}" -C "$path" changelog notes "$version" --output "$output" >&2 ||
      die "inspectra changelog notes found no notes for $version in $path; the release stops here."
    ;;
  changelog)
    changelog_section || die "$path/CHANGELOG.md has no section for $version."
    ;;
  file)
    [[ -f "${NOTES_FILE:-}" ]] || die "The notes file '${NOTES_FILE:-}' does not exist."
    cp "$NOTES_FILE" "$output"
    ;;
  generate | keep) : >"$output" ;;
  *) die "Unknown notes source '$source_mode'." ;;
esac
echo "$source_mode"
