#!/usr/bin/env bash
# Runs an Inspectra command and turns its exit code into a clear annotation.
#
#   0   passed
#   1   findings at or above the threshold, or a failed gate
#   64  usage error (a wrong option of this workflow or of the configuration)
#   65  invalid input or configuration, including a policy violation
#   69  incomplete: a network service or a tool (Trivy, git, dart) was unavailable
#   70  internal error of Inspectra
#
# Usage: run.sh <label> <inspectra arguments...>
# Environment:
#   INSPECTRA            the command that runs Inspectra
#   TOLERATE_INCOMPLETE  true turns exit code 69 into a warning
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

label="$1"
shift
read -r -a command <<<"${INSPECTRA:?INSPECTRA is required}"
"${command[@]}" "$@"
status=$?

case "$status" in
  0) exit 0 ;;
  1) echo "::error title=Inspectra ${label}::Findings at or above the threshold, or a failed gate. See the log and the job summary." ;;
  64) echo "::error title=Inspectra ${label}::Usage error (exit code 64): an option of the workflow or the configuration is not valid for this Inspectra version." ;;
  65) echo "::error title=Inspectra ${label}::Invalid input or configuration (exit code 65), including a violated policy." ;;
  69)
    if [[ "${TOLERATE_INCOMPLETE:-false}" == true ]]; then
      echo "::warning title=Inspectra ${label}::Incomplete (exit code 69): a network service or a tool was unavailable; tolerated."
      exit 0
    fi
    echo "::error title=Inspectra ${label}::Incomplete (exit code 69): a network service or a tool (Trivy, git, dart) was unavailable. tolerate-incomplete turns this into a warning."
    ;;
  70) echo "::error title=Inspectra ${label}::Internal error of Inspectra (exit code 70); rerun with INSPECTRA_DEBUG=1 for the stack trace." ;;
  *) echo "::error title=Inspectra ${label}::Exit code $status." ;;
esac
exit "$status"
