#!/usr/bin/env bash
# Assembles one GitHub Pages site from the parts of a run.
#
# Every part is a directory with a .davils-part.json ({"part": "docs", "id": "d"}), downloaded from
# an artifact davils-pages-*. LAYOUT maps a part to its path in the site, {id} is replaced by the
# id of the part. Two parts writing the same file is an error; a part may sit inside another
# (docs at / and api at /api) as long as no file overlaps.
#
# Flutter web builds get the <base href> of their path, prefixed with the base path of the site
# (/<repository> for a project site, empty for a custom domain).
#
# Environment:
#   IN_DIR        directory with one subdirectory per downloaded part
#   OUT_DIR       the site
#   LAYOUT        JSON object: part -> path
#   BASE_PATH     base path of the site from actions/configure-pages, such as /workflows
#   LANDING_PAGE  auto (when nothing is at /), true or false
#   CNAME         custom domain, written to CNAME
#   SPA_FALLBACK  id of a web part whose index.html also serves as 404.html
#   EXTRA_PATH    directory of the repository copied into the site root
#   TITLE         title of the landing page
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

IN_DIR="${IN_DIR:?IN_DIR is required}"
OUT_DIR="${OUT_DIR:?OUT_DIR is required}"
layout="${LAYOUT:-}"
[[ -z "$layout" ]] && layout='{"docs":"/","api":"/api","web":"/app/{id}","coverage":"/coverage/{id}","inspectra":"/quality"}'
base="${BASE_PATH:-}"
base="${base%/}"
mkdir -p "$OUT_DIR"
manifest="$(mktemp)"
parts='[]'

# Copies a directory into the site and fails on files that already exist there.
place() {
  local source="$1" target="$2" label="$3"
  local collisions=()
  while IFS= read -r -d '' file; do
    local relative="${file#"$source"/}"
    [[ "$relative" == .davils-part.json ]] && continue
    local destination="$OUT_DIR${target%/}/$relative"
    if [[ -e "$destination" ]]; then
      collisions+=("${target%/}/$relative ($(grep -F -- "${target%/}/$relative" "$manifest" | head -1 | cut -f2) and $label)")
      continue
    fi
    mkdir -p "$(dirname "$destination")"
    cp -p "$file" "$destination"
    printf '%s\t%s\n' "${target%/}/$relative" "$label" >>"$manifest"
  done < <(find "$source" -type f -print0)
  if ((${#collisions[@]} > 0)); then
    printf '::error::Pages parts overlap: %s\n' "${collisions[@]}"
    die "Change pages.layout so the parts do not overlap."
  fi
}

shopt -s nullglob
for dir in "$IN_DIR"/*/; do
  dir="${dir%/}"
  meta="$dir/.davils-part.json"
  if [[ ! -f "$meta" ]]; then
    warn "$(basename "$dir") has no .davils-part.json; skipped."
    continue
  fi
  part="$(jq -r '.part' "$meta")"
  id="$(jq -r '.id // ""' "$meta")"
  target="$(jq -r --arg p "$part" '.[$p] // empty' <<<"$layout")"
  if [[ -z "$target" ]]; then
    warn "pages.layout has no path for the part '$part'; $(basename "$dir") skipped."
    continue
  fi
  target="${target//\{id\}/$id}"
  [[ "$target" == /* ]] || target="/$target"
  echo "$part ($id) -> $target"
  place "$dir" "$target" "$part:$id"

  # A Flutter web build resolves its assets against <base href>; it has to name the final path.
  if [[ "$part" == web && -f "$OUT_DIR${target%/}/index.html" ]]; then
    href="${base}${target%/}/"
    sed -i.bak -E "s#<base href=\"[^\"]*\"#<base href=\"${href}\"#" "$OUT_DIR${target%/}/index.html"
    rm -f "$OUT_DIR${target%/}/index.html.bak"
  fi
  parts="$(jq -c --arg part "$part" --arg id "$id" --arg path "${target%/}/" '. + [{part: $part, id: $id, path: $path}]' <<<"$parts")"
done

if [[ -n "${EXTRA_PATH:-}" ]]; then
  [[ -d "$EXTRA_PATH" ]] || die "pages extra-path '$EXTRA_PATH' does not exist."
  place "$EXTRA_PATH" / "extra-path"
fi

landing="${LANDING_PAGE:-auto}"
if [[ "$landing" == true || ("$landing" == auto && ! -f "$OUT_DIR/index.html") ]]; then
  if [[ -f "$OUT_DIR/index.html" ]]; then
    warn "landing-page is true but a part already provides index.html; the part wins."
  else
    title="${TITLE:-Documentation}"
    {
      echo '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
      echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
      printf '<title>%s</title>\n' "$title"
      echo '<style>body{font-family:system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1rem;line-height:1.5}a{color:#0b6bcb}li{margin:.5rem 0}small{color:#666}</style>'
      printf '</head><body><h1>%s</h1><ul>\n' "$title"
      jq -r --arg base "$base" '
        {docs: "Documentation", api: "API reference", web: "App", coverage: "Coverage", inspectra: "Quality dashboard"} as $names
        | .[] | "<li><a href=\"\($base)\(.path)\">\($names[.part] // .part)</a> <small>\(.id)</small></li>"' <<<"$parts"
      echo '</ul></body></html>'
    } >"$OUT_DIR/index.html"
  fi
fi

if [[ -n "${SPA_FALLBACK:-}" ]]; then
  path="$(jq -r --arg id "$SPA_FALLBACK" '.[] | select(.part == "web" and .id == $id) | .path' <<<"$parts")"
  [[ -n "$path" ]] || die "spa-fallback names '$SPA_FALLBACK', but no web part has that id."
  cp "$OUT_DIR${path}index.html" "$OUT_DIR/404.html"
fi

[[ -n "${CNAME:-}" ]] && printf '%s\n' "$CNAME" >"$OUT_DIR/CNAME"
touch "$OUT_DIR/.nojekyll"
rm -f "$manifest"

[[ "$(jq 'length' <<<"$parts")" -gt 0 || -n "${EXTRA_PATH:-}" ]] || die "No Pages part was found; nothing to deploy."

set_output parts "$parts"
{
  echo "### GitHub Pages"
  echo
  echo "| Part | Id | Path |"
  echo "|---|---|---|"
  jq -r --arg base "$base" '.[] | "| \(.part) | \(.id) | `\($base)\(.path)` |"' <<<"$parts"
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
