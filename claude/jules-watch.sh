#!/usr/bin/env bash
# jules-watch.sh <session_id> [timeout_minutes]
# A zero-token watcher for Claude Code. Start it from the main thread with the Bash tool's run_in_background: it has no
# 10-minute cap and the harness wakes the agent when it exits, so nothing is polling and nobody has to remember to
# restart a bounded wait (a bounded sub-agent wait ended minutes before Jules asked a question, twice).
# It exits with the same code as `jules-gate wait` and prints one final line the agent can act on:
#   JULES_RESULT status=COMPLETED|NEEDS_INPUT|TIMEOUT|FAILED session=<id>
set -uo pipefail

SID="${1:-}"
MINUTES="${2:-480}"
if [[ -z "$SID" || ! "$SID" =~ ^[0-9]+$ ]]; then
    echo "Usage: $0 <session_id> [timeout_minutes]" >&2
    exit 64
fi

jules-gate wait "$SID" --interactive --timeout "$MINUTES"
rc=$?
case "$rc" in
    0)  status=COMPLETED ;;
    10) status=NEEDS_INPUT
        jules-gate inspect "$SID" 2>&1 | head -n 40 ;;
    1)  status=TIMEOUT ;;
    *)  status=FAILED ;;
esac
echo "JULES_RESULT status=$status session=$SID"
exit "$rc"
