#!/usr/bin/env bash
# jules_poll_wait.sh - Token-free session watcher for Google Jules (EULIS)
# Waits for one or more Jules sessions to finish without triggering LLM round-trips.
# Fully compatible with macOS default Bash 3.2 and modern Bash 4/5.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

usage() {
    echo "Usage: $0 [--timeout MINS] [--interactive|-i] <session_id> [<session_id2> ...]"
    exit 1
}

TIMEOUT_MINS=30
INTERACTIVE_MODE=false
SESSIONS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT_MINS="$2"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE_MODE=true
            shift
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
AWAITING_FEEDBACK_SESSIONS=" "
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
        if [[ "$COMPLETED_SESSIONS" == *" $SID "* || "$AWAITING_FEEDBACK_SESSIONS" == *" $SID "* || "$FAILED_SESSIONS" == *" $SID "* ]]; then
            continue
        fi

        # Find status of session in list output
        STATUS_LINE=$(echo "$LIST_OUTPUT" | grep -E "\b$SID\b" || true)
        if [[ -z "$STATUS_LINE" ]]; then
            ALL_DONE=false
            continue
        fi

        if echo "$STATUS_LINE" | grep -qi "Completed"; then
            echo "✅ [DONE: Completed] Session $SID finalized remotely."
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            COMPLETED_SESSIONS="${COMPLETED_SESSIONS}${SID} "
        elif echo "$STATUS_LINE" | grep -qiE "Awaiting User"; then
            echo "⚡ [INTERACTIVE: Awaiting User Feedback] Session $SID requires user response!"
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            API_SCRIPT="$SCRIPT_DIR/jules_api.py"
            AUTO_RESOLVED=false
            if [[ -x "$API_SCRIPT" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo "   🤖 [--interactive] Evaluating auto-answer heuristics for session $SID..."
                    if python3 "$API_SCRIPT" auto-answer "$SID" 2>&1; then
                        echo "   ✅ Automatically resolved boilerplate prompt. Resuming token-free watcher..."
                        AUTO_RESOLVED=true
                        sleep 10
                    else
                        echo "   ⚡ Prompt is substantive: requires manual or escalated decision."
                    fi
                fi
                if [[ "$AUTO_RESOLVED" == "false" ]]; then
                    INSPECT_JSON=$(python3 "$API_SCRIPT" inspect "$SID" --json 2>/dev/null || true)
                    QUESTION=$(echo "$INSPECT_JSON" | grep -o '"question": *"[^"]*"' | sed -E 's/"question": *"([^"]*)"/\1/' || true)
                    if [[ -n "$QUESTION" ]]; then
                        echo "   ❓ Jules Question: $QUESTION"
                    fi
                fi
            fi

            if [[ "$AUTO_RESOLVED" == "true" ]]; then
                ALL_DONE=false
            else
                echo "   ⛔ STRICT GUARD: Task is in interactive state. DO NOT MERGE. DO NOT CONSIDER COMPLETED."
                echo "   💡 Action: Use 'jules-gate interact $SID \"<answer>\"' to unblock Jules."
                AWAITING_FEEDBACK_SESSIONS="${AWAITING_FEEDBACK_SESSIONS}${SID} "
            fi
        elif echo "$STATUS_LINE" | grep -qi "Failed"; then
            echo "❌ [FAILED] Session $SID failed remotely!"
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            FAILED_SESSIONS="${FAILED_SESSIONS}${SID} "
        else
            ALL_DONE=false
        fi
    done

    # Check if all sessions have reached a terminal state
    for SID in "${SESSIONS[@]}"; do
        if [[ "$COMPLETED_SESSIONS" != *" $SID "* && "$AWAITING_FEEDBACK_SESSIONS" != *" $SID "* && "$FAILED_SESSIONS" != *" $SID "* ]]; then
            ALL_DONE=false
            break
        fi
    done

    if $ALL_DONE; then
        echo "🎉 All requested Jules sessions have concluded."
        for SID in "${SESSIONS[@]}"; do
            if [[ "$COMPLETED_SESSIONS" == *" $SID "* ]]; then
                echo "  - Session $SID: Completed (https://jules.google.com/task/$SID)"
            elif [[ "$AWAITING_FEEDBACK_SESSIONS" == *" $SID "* ]]; then
                echo "  - Session $SID: Interactive / Awaiting User Feedback (https://jules.google.com/task/$SID)"
            else
                echo "  - Session $SID: Failed (https://jules.google.com/task/$SID)"
            fi
        done
        break
    fi

    sleep 30
done

# Check if any session is in interactive state (Exit Code 10)
for SID in "${SESSIONS[@]}"; do
    if [[ "$AWAITING_FEEDBACK_SESSIONS" == *" $SID "* ]]; then
        echo ""
        echo "⚠️  [INTERACTIVE GUARD ACTIVATED] One or more sessions are awaiting input (Exit code 10)."
        echo "   Do NOT merge review branches. Provide answers via 'jules-gate interact <session_id> \"<answer>\"'."
        exit 10
    fi
done

# Exit non-zero if any session failed (Exit Code 2)
for SID in "${SESSIONS[@]}"; do
    if [[ "$FAILED_SESSIONS" == *" $SID "* ]]; then
        exit 2
    fi
done

exit 0
