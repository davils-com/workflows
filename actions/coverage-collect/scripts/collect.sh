#!/usr/bin/env bash
# Merges the lcov files of several packages, computes the line coverage per package and in total,
# enforces a minimum and renders an HTML report.
#
# Environment:
#   IN_DIR     directory with <package>.lcov files
#   OUT_DIR    directory for lcov.info, summary.md and html/
#   MIN        minimum total line coverage in percent; 0 disables the check
#   HTML       true to render html/ with genhtml
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

IN_DIR="${IN_DIR:?IN_DIR is required}"
OUT_DIR="${OUT_DIR:?OUT_DIR is required}"
mkdir -p "$OUT_DIR"

shopt -s nullglob
files=("$IN_DIR"/*.lcov)
if ((${#files[@]} == 0)); then
  warn "No coverage was collected."
  set_output percent ''
  exit 0
fi
cat "${files[@]}" >"$OUT_DIR/lcov.info"

# LF lines found, LH lines hit, per file record; summed per package and in total.
rows=''
total_found=0
total_hit=0
for file in "${files[@]}"; do
  name="$(basename "$file" .lcov)"
  read -r found hit < <(awk -F: '/^LF:/ {f += $2} /^LH:/ {h += $2} END {print f + 0, h + 0}' "$file")
  total_found=$((total_found + found))
  total_hit=$((total_hit + hit))
  percent="$(awk -v h="$hit" -v f="$found" 'BEGIN { if (f == 0) print "n/a"; else printf "%.2f", 100 * h / f }')"
  rows+="| $name | $hit / $found | $percent % |"$'\n'
done
total="$(awk -v h="$total_hit" -v f="$total_found" 'BEGIN { if (f == 0) print "0"; else printf "%.2f", 100 * h / f }')"

{
  echo "### Coverage"
  echo
  echo "| Package | Lines | Coverage |"
  echo "|---|---|---|"
  printf '%s' "$rows"
  echo "| **Total** | $total_hit / $total_found | **$total %** |"
} >"$OUT_DIR/summary.md"
cat "$OUT_DIR/summary.md" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
set_output percent "$total"
set_output lcov "$OUT_DIR/lcov.info"

if [[ "${HTML:-false}" == true ]]; then
  if ! command -v genhtml >/dev/null 2>&1; then
    sudo apt-get install -y -qq lcov >/dev/null 2>&1 || brew install lcov >/dev/null 2>&1 || true
  fi
  if command -v genhtml >/dev/null 2>&1; then
    genhtml --quiet --ignore-errors source,unmapped --output-directory "$OUT_DIR/html" --title "Coverage" "$OUT_DIR/lcov.info" ||
      warn "genhtml could not render the coverage report."
  else
    warn "genhtml is not available; no HTML coverage report."
  fi
fi

min="${MIN:-0}"
if [[ -n "$min" && "$min" != 0 ]]; then
  if awk -v t="$total" -v m="$min" 'BEGIN { exit !(t + 0 < m + 0) }'; then
    die "The line coverage is $total %, below the minimum of $min %."
  fi
  echo "The line coverage is $total %, the minimum is $min %."
fi
