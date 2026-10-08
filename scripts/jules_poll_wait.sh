#!/usr/bin/env bash
# jules_poll_wait.sh - Token-free session watcher for Google Jules (EULIS)
# Waits for one or more Jules sessions to finish without triggering LLM round-trips.
# Fully compatible with macOS default Bash 3.2 and modern Bash 4/5.

set -euo pipefail

usage() {
    echo "Usage: $0 [--timeout MINS] <session_id> [<session_id2> ...]"
    exit 1
}

TIMEOUT_MINS=30
SESSIONS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT_MINS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            SESSIONS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#SESSIONS[@]} -eq 0 ]]; then
    usage
fi

echo "=========================================================="
echo " [Jules Watcher] Monitoring ${#SESSIONS[@]} session(s) with zero token cost"
echo " Timeout: ${TIMEOUT_MINS} minutes | Polling interval: 30s"
echo " Sessions: ${SESSIONS[*]}"
echo "=========================================================="

START_TIME=$(date +%s)
TIMEOUT_SECS=$((TIMEOUT_MINS * 60))

COMPLETED_SESSIONS=" "
FAILED_SESSIONS=" "

while true; do
    ALL_DONE=true
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))

    if [[ $ELAPSED -ge $TIMEOUT_SECS ]]; then
        echo "❌ [TIMEOUT] Exceeded ${TIMEOUT_MINS} minutes waiting for sessions."
        exit 1
    fi

    LIST_OUTPUT=$(jules remote list --session 2>&1 || true)

    for SID in "${SESSIONS[@]}"; do
        # Check if already processed
        if [[ "$COMPLETED_SESSIONS" == *" $SID "* || "$FAILED_SESSIONS" == *" $SID "* ]]; then
            continue
        fi

        # Find status of session in list output
        STATUS_LINE=$(echo "$LIST_OUTPUT" | grep -E "\b$SID\b" || true)
        if [[ -z "$STATUS_LINE" ]]; then
            ALL_DONE=false
            continue
        fi

        if echo "$STATUS_LINE" | grep -qi "Completed"; then
            echo "✅ [DONE] Session $SID completed successfully!"
            COMPLETED_SESSIONS="${COMPLETED_SESSIONS}${SID} "
        elif echo "$STATUS_LINE" | grep -qi "Failed"; then
            echo "❌ [FAILED] Session $SID failed remotely!"
            FAILED_SESSIONS="${FAILED_SESSIONS}${SID} "
        else
            ALL_DONE=false
        fi
    done

    # Check if all sessions have reached a terminal state
    for SID in "${SESSIONS[@]}"; do
        if [[ "$COMPLETED_SESSIONS" != *" $SID "* && "$FAILED_SESSIONS" != *" $SID "* ]]; then
            ALL_DONE=false
            break
        fi
    done

    if $ALL_DONE; then
        echo "🎉 All requested Jules sessions have concluded."
        for SID in "${SESSIONS[@]}"; do
            if [[ "$COMPLETED_SESSIONS" == *" $SID "* ]]; then
                echo "  - Session $SID: Completed"
            else
                echo "  - Session $SID: Failed"
            fi
        done
        break
    fi

    sleep 30
done

# Exit non-zero if any session failed
for SID in "${SESSIONS[@]}"; do
    if [[ "$FAILED_SESSIONS" == *" $SID "* ]]; then
        exit 2
    fi
done

exit 0
