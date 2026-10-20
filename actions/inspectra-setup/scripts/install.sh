#!/usr/bin/env bash
# Makes Inspectra available and prints the command that runs it.
#
#   dev-dependency  dart run inspectra, the version of the lockfile (pub get has to be done)
#   global          dart pub global activate inspectra [version]
#   binary          the native executable of a GitHub release of davils-com/Inspectra, verified
#                   against the checksums.txt of that release
#   auto            dev-dependency when the root pubspec.yaml depends on inspectra, global otherwise
#
# Environment:
#   MODE          auto, dev-dependency, global or binary
#   VERSION       latest or a version such as 2.1.0 (global and binary)
#   REPOSITORY    the repository of the binaries (default davils-com/Inspectra)
#   GITHUB_TOKEN  raises the API rate limit for the release lookup
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

mode="${MODE:-auto}"
version="${VERSION:-latest}"
repository="${REPOSITORY:-davils-com/Inspectra}"

if [[ "$mode" == auto ]]; then
  # The dev dependency, or the Inspectra repository itself, which checks itself with its source.
  if [[ -f pubspec.yaml ]] && [[ "$(yq -r '(.dev_dependencies // {} | has("inspectra")) or (.dependencies // {} | has("inspectra")) or .name == "inspectra"' pubspec.yaml)" == true ]]; then
    mode=dev-dependency
  else
    mode=global
  fi
fi

case "$mode" in
  dev-dependency)
    command='dart run inspectra'
    ;;
  global)
    if [[ "$version" == latest ]]; then
      dart pub global activate inspectra >&2
    else
      dart pub global activate inspectra "$version" >&2
    fi
    command='dart pub global run inspectra'
    ;;
  binary)
    case "${RUNNER_OS:-$(uname -s)}-${RUNNER_ARCH:-$(uname -m)}" in
      Linux-X64 | Linux-x86_64) target=linux-x64 ;;
      Linux-ARM64 | Linux-aarch64) target=linux-arm64 ;;
      macOS-ARM64 | Darwin-arm64) target=macos-arm64 ;;
      macOS-X64 | Darwin-x86_64) target=macos-x64 ;;
      Windows-X64 | MINGW*) target=windows-x64 ;;
      *) die "No Inspectra binary for ${RUNNER_OS:-}-${RUNNER_ARCH:-}; use install: global." ;;
    esac
    auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    api="https://api.github.com/repos/$repository/releases"
    if [[ "$version" == latest ]]; then
      release="$(curl -fsSL "${auth[@]}" "$api/latest")"
    else
      release="$(curl -fsSL "${auth[@]}" "$api/tags/v$version" 2>/dev/null || curl -fsSL "${auth[@]}" "$api/tags/$version")"
    fi
    tag="$(jq -r '.tag_name' <<<"$release")"
    asset_url() { jq -r --arg n "$1" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$release"; }
    zip_url="$(asset_url "inspectra-$target.zip")"
    sums_url="$(asset_url checksums.txt)"
    [[ -n "$zip_url" ]] || die "Release $tag of $repository has no inspectra-$target.zip."
    [[ -n "$sums_url" ]] || die "Release $tag of $repository has no checksums.txt; refusing an unverified binary."
    dir="${RUNNER_TOOL_CACHE:-${RUNNER_TEMP:-/tmp}}/inspectra/$tag/$target"
    mkdir -p "$dir"
    curl -fsSL -o "$dir/inspectra-$target.zip" "$zip_url"
    curl -fsSL -o "$dir/checksums.txt" "$sums_url"
    expected="$(awk -v n="inspectra-$target.zip" '$2 == n || $2 == "*" n {print $1}' "$dir/checksums.txt")"
    [[ -n "$expected" ]] || die "checksums.txt of $tag lists no inspectra-$target.zip."
    if command -v sha256sum >/dev/null; then
      actual="$(sha256sum "$dir/inspectra-$target.zip" | awk '{print $1}')"
    else
      actual="$(shasum -a 256 "$dir/inspectra-$target.zip" | awk '{print $1}')"
    fi
    [[ "$expected" == "$actual" ]] || die "The checksum of inspectra-$target.zip does not match checksums.txt of $tag."
    unzip -oq "$dir/inspectra-$target.zip" -d "$dir"
    executable="$(find "$dir" -maxdepth 2 -type f \( -name inspectra -o -name inspectra.exe \) | head -1)"
    [[ -n "$executable" ]] || die "inspectra-$target.zip contains no inspectra executable."
    chmod +x "$executable"
    command="$executable"
    ;;
  *) die "Unknown install mode '$mode'; use auto, dev-dependency, global or binary." ;;
esac

echo "Inspectra: $mode ($($command --version 2>/dev/null | head -1 || echo unknown version))" >&2
set_output command "$command"
set_output mode "$mode"
