#!/usr/bin/env bash
# Pushes release tags in batches of three.
#
# GitHub starts no workflow for any tag when more than three tags arrive in one push, so a
# workspace release of many packages would silently publish nothing. This script pushes the given
# tags, or every local tag the remote does not have yet, three at a time.
#
# Usage: tools/push-tags.sh [--remote origin] [--pause 5] [tag...]
set -euo pipefail

remote=origin
pause=5
tags=()
while (($# > 0)); do
  case "$1" in
    --remote) remote="$2"; shift 2 ;;
    --pause) pause="$2"; shift 2 ;;
    -h | --help) sed -n '2,9p' "$0"; exit 0 ;;
    *) tags+=("$1"); shift ;;
  esac
done

if ((${#tags[@]} == 0)); then
  remote_tags="$(git ls-remote --tags --refs "$remote" | sed 's#.*refs/tags/##' | sort)"
  while IFS= read -r tag; do
    [[ -n "$tag" ]] && tags+=("$tag")
  done < <(comm -23 <(git tag --list | sort) <(printf '%s\n' "$remote_tags"))
fi

if ((${#tags[@]} == 0)); then
  echo "No tags to push."
  exit 0
fi

for ((i = 0; i < ${#tags[@]}; i += 3)); do
  batch=("${tags[@]:i:3}")
  echo "Pushing ${batch[*]}"
  git push "$remote" "${batch[@]/#/refs/tags/}"
  if ((i + 3 < ${#tags[@]})); then
    sleep "$pause"
  fi
done
