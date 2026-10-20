#!/usr/bin/env bash
# Checks a release tag: it matches a tag pattern, names a package of the repository, carries the
# version of that package's pubspec.yaml and points to a commit of the release branch.
#
# Environment:
#   TAG             the tag, such as v1.2.3 or core-v1.2.3
#   TAG_PATTERNS    JSON object of patterns with {package} and {version}; default
#                   {"single": "v{version}", "package": "{package}-v{version}"}
#   DISCOVERY       output of discover-packages
#   RELEASE_BRANCH  branch the tagged commit has to be on; empty skips the check
#   SHA             the tagged commit (default HEAD)
#
# Prints {"package", "path", "version", "kind", "prerelease", "publishable", "toolchain",
# "workspace", "app", "executables", "internal_dependencies"}.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

TAG="${TAG:?TAG is required}"
TAG="${TAG#refs/tags/}"
DISCOVERY="${DISCOVERY:?DISCOVERY is required}"
patterns="${TAG_PATTERNS:-}"
[[ -z "$patterns" ]] && patterns='{"single":"v{version}","package":"{package}-v{version}"}'

parsed="$(jq -c -L "$here/../../_lib" --arg tag "$TAG" 'include "lib"; parse_tag($tag; .)' <<<"$patterns")"
[[ "$parsed" != null ]] || die "The tag $TAG matches none of the tag patterns $(jq -r '[.[]] | join(", ")' <<<"$patterns")."

version="$(jq -r '.version' <<<"$parsed")"
kind="$(jq -r '.kind' <<<"$parsed")"
package_name="$(jq -r '.package // empty' <<<"$parsed")"

if [[ -n "$package_name" ]]; then
  package="$(jq -c --arg n "$package_name" '.packages[] | select(.name == $n)' <<<"$DISCOVERY")"
  [[ -n "$package" ]] || die "The tag $TAG names the package $package_name, which this repository does not have. Packages: $(jq -r '[.packages[].name] | join(", ")' <<<"$DISCOVERY")."
else
  package="$(jq -c '.packages[] | select(.path == ".")' <<<"$DISCOVERY")"
  if [[ -z "$package" ]]; then
    count="$(jq '[.packages[] | select(.publishable)] | length' <<<"$DISCOVERY")"
    if [[ "$count" == 1 ]]; then
      package="$(jq -c '.packages[] | select(.publishable)' <<<"$DISCOVERY")"
    else
      die "The tag $TAG names no package, and the repository is a workspace with $count publishable packages. Tag <package>-v<version> instead."
    fi
  fi
fi

declared="$(jq -r '.version' <<<"$package")"
name="$(jq -r '.name' <<<"$package")"
path="$(jq -r '.path' <<<"$package")"
# A build number (+1) in the pubspec.yaml does not have to be in the tag.
if [[ "$declared" != "$version" && "${declared%%+*}" != "$version" ]]; then
  die "The tag $TAG carries version $version, but $path/pubspec.yaml of $name has version ${declared:-none}."
fi

if [[ -n "${RELEASE_BRANCH:-}" ]]; then
  sha="${SHA:-HEAD}"
  if ! git rev-parse --verify --quiet "origin/$RELEASE_BRANCH" >/dev/null; then
    git fetch --no-tags --quiet origin "+refs/heads/$RELEASE_BRANCH:refs/remotes/origin/$RELEASE_BRANCH" ||
      die "The release branch $RELEASE_BRANCH could not be fetched."
  fi
  git merge-base --is-ancestor "$sha" "origin/$RELEASE_BRANCH" ||
    die "The tag $TAG is not on $RELEASE_BRANCH. Releases are tagged on the release branch."
fi

prerelease=false
[[ "$version" == *-* ]] && prerelease=true

jq -c --arg version "$version" --arg kind "$kind" --argjson prerelease "$prerelease" --arg tag "$TAG" '
  {tag: $tag, package: .name, name, path, version: $version, kind: $kind, prerelease: $prerelease,
   publishable, toolchain, workspace, app, executables, internal_dependencies, inspectra, has_tests}
' <<<"$package"
