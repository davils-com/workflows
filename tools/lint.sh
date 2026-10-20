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
(cd "$work" && git init -q && actionlint -config-file .github/actionlint.yaml) || status=1

if [[ -d examples ]]; then
  while IFS= read -r file; do
    actionlint -config-file .github/actionlint.yaml "$file" || status=1
  done < <(find examples -path '*/.github/workflows/*.yml' 2>/dev/null)
fi

mapfile -t scripts < <(find actions tools tests/scripts -name '*.sh' -type f 2>/dev/null | sort)
if ((${#scripts[@]} > 0)); then
  shellcheck -x "${scripts[@]}" || status=1
fi

zizmor --config .github/zizmor.yml --min-severity low --no-progress .github/workflows actions || status=1

exit "$status"
