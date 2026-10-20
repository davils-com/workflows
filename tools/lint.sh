#!/usr/bin/env bash
# Lints the workflows, the composite actions and the scripts of this repository.
#
# - actionlint checks the workflows and examples. It does not know the self-repository syntax
#   yet, so $/ references are rewritten to ./ in a copy first; that also lets it check the inputs
#   of the local actions.
# - ShellCheck checks every script under actions/, tools/ and tests/.
# - zizmor audits the workflows and the composite actions.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/.github"
cp -R .github/workflows "$work/.github/workflows"
cp .github/actionlint.yaml "$work/.github/actionlint.yaml"
cp -R actions "$work/actions"
find "$work" -name '*.yml' -print0 | xargs -0 sed -i.bak -E 's#uses: \$/#uses: ./#'
find "$work" -name '*.bak' -delete
# In GitHub Actions every finding becomes an annotation.
actionlint_format=()
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  # shellcheck disable=SC2016
  actionlint_format=(-format '{{range $err := .}}::error file={{$err.Filepath}},line={{$err.Line}},col={{$err.Column}}::{{$err.Message}}\n{{end}}')
fi
(cd "$work" && git init -q && actionlint -config-file .github/actionlint.yaml "${actionlint_format[@]}") || status=1

if [[ -d examples ]]; then
  while IFS= read -r file; do
    actionlint -config-file .github/actionlint.yaml "${actionlint_format[@]}" "$file" || status=1
  done < <(find examples -path '*/.github/workflows/*.yml' 2>/dev/null)
fi

mapfile -t scripts < <(find actions tools tests/scripts -name '*.sh' -type f 2>/dev/null | sort)
if ((${#scripts[@]} > 0)); then
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    shellcheck -x -f gcc "${scripts[@]}" | sed -E 's/^([^:]+):([0-9]+):([0-9]+): ([a-z]+): (.*)$/::error file=\1,line=\2,col=\3::\5/' || true
  fi
  shellcheck -x "${scripts[@]}" || status=1
fi

zizmor_format=()
[[ -n "${GITHUB_ACTIONS:-}" ]] && zizmor_format=(--format github)
zizmor --config .github/zizmor.yml --min-severity low --no-progress "${zizmor_format[@]}" .github/workflows actions || status=1

exit "$status"
