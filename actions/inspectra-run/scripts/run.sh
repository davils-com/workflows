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
#   TIMEOUT_MINUTES      stops the run after this many minutes and reports the hanging processes
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$here/../../_lib/common.sh"

label="$1"
shift
read -r -a command <<<"${INSPECTRA:?INSPECTRA is required}"

# Nothing may wait for input: no stdin, no git credential prompt.
export GIT_TERMINAL_PROMPT=0

# A watchdog: when the run takes longer than TIMEOUT_MINUTES, the process tree goes into an
# annotation (which process hangs is visible without the log) before the run is stopped.
"${command[@]}" "$@" </dev/null &
pid=$!
limit=$((${TIMEOUT_MINUTES:-0} * 60))
if ((limit > 0)); then
  (
    sleep "$limit"
    if kill -0 "$pid" 2>/dev/null; then
      tree="$(ps -eo pid,ppid,etime,args 2>/dev/null | awk -v root="$pid" '
        NR == 1 { print; next }
        { pid[NR] = $1; ppid[NR] = $2; line[NR] = $0 }
        END {
          keep[root] = 1
          for (changed = 1; changed; ) {
            changed = 0
            for (i in pid) if (keep[ppid[i]] && !keep[pid[i]]) { keep[pid[i]] = 1; changed = 1 }
          }
          for (i in pid) if (keep[pid[i]]) print substr(line[i], 1, 200)
        }' | head -40)"
      echo "::error title=Inspectra ${label} timed out::It ran longer than ${TIMEOUT_MINUTES} minutes. The processes:%0A$(sed 's/%/%25/g' <<<"$tree" | awk 'BEGIN { ORS = "%0A" } 1')"
      pkill -TERM -P "$pid" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null
    fi
  ) &
  watchdog=$!
fi
wait "$pid"
status=$?
[[ -n "${watchdog:-}" ]] && kill "$watchdog" 2>/dev/null

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
