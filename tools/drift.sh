#!/usr/bin/env bash
# Sourced by the generators: reports a generated file that differs from the committed one, with
# the first lines of the difference in the annotation, so CI shows what changed without the log.

# Usage: report_drift <file or directory> <generator> <diff output>
report_drift() {
  local target="$1" generator="$2" diff="$3"
  printf '%s\n' "$diff"
  local excerpt
  excerpt="$(printf '%s\n' "$diff" | grep -E '^[-+][^-+]' | head -15 | sed 's/%/%25/g' | awk 'BEGIN { ORS = "%0A" } 1')"
  echo "::error title=Stale generated file::${target} is stale; run ${generator}.%0A${excerpt}"
}
