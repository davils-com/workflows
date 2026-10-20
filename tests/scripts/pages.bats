#!/usr/bin/env bats
# Assembling the Pages site from parts.

load helpers

part() {
  local name="$1" part="$2" id="$3"
  mkdir -p "$IN/$name"
  jq -cn --arg p "$part" --arg i "$id" '{part: $p, id: $i}' >"$IN/$name/.davils-part.json"
  echo "$IN/$name"
}

assemble() {
  IN_DIR="$IN" OUT_DIR="$OUT" run_script "$ACTIONS/pages-assemble/scripts/assemble.sh"
}

setup() {
  IN="$BATS_TEST_TMPDIR/in"
  OUT="$BATS_TEST_TMPDIR/out"
  mkdir -p "$IN"
}

@test "parts land at their layout paths" {
  docs="$(part davils-pages-docs-d docs d)"
  echo docs >"$docs/index.html"
  api="$(part davils-pages-api api api)"
  echo api >"$api/index.html"
  web="$(part davils-pages-web-demo web demo)"
  printf '<html><head><base href="/"></head></html>\n' >"$web/index.html"
  BASE_PATH=/workflows run assemble
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/index.html")" = docs ]
  [ "$(cat "$OUT/api/index.html")" = api ]
  grep -q '<base href="/workflows/app/demo/"' "$OUT/app/demo/index.html"
  [ -f "$OUT/.nojekyll" ]
  [ ! -f "$OUT/.davils-part.json" ]
}

@test "a landing page is written when no part provides one" {
  api="$(part davils-pages-api api api)"
  echo api >"$api/index.html"
  coverage="$(part davils-pages-coverage-dart coverage dart)"
  echo cov >"$coverage/index.html"
  TITLE='Fixture' BASE_PATH=/repo run assemble
  [ "$status" -eq 0 ]
  grep -q 'href="/repo/api/"' "$OUT/index.html"
  grep -q 'href="/repo/coverage/dart/"' "$OUT/index.html"
  grep -q '<title>Fixture</title>' "$OUT/index.html"
}

@test "overlapping files are an error" {
  docs="$(part davils-pages-docs-d docs d)"
  mkdir -p "$docs/api"
  echo docs >"$docs/api/index.html"
  api="$(part davils-pages-api api api)"
  echo api >"$api/index.html"
  run assemble
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlap"* ]]
}

@test "the layout, a custom domain and the SPA fallback are honoured" {
  web="$(part davils-pages-web-shop web shop)"
  printf '<base href="/">\n' >"$web/index.html"
  LAYOUT='{"web": "/"}' CNAME=docs.example.test SPA_FALLBACK=shop run assemble
  [ "$status" -eq 0 ]
  grep -q '<base href="/"' "$OUT/index.html"
  [ "$(cat "$OUT/CNAME")" = docs.example.test ]
  [ -f "$OUT/404.html" ]
}

@test "without any part there is nothing to deploy" {
  run assemble
  [ "$status" -ne 0 ]
  [[ "$output" == *"No Pages part"* ]]
}
