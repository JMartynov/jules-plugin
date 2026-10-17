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

# Run a command and kill it after N seconds, so one stuck call cannot freeze the whole watcher.
# macOS has no `timeout`, so this uses a background watchdog. Exit code 143 means it was killed.
CALL_TIMEOUT_SECS="${JULES_CALL_TIMEOUT:-60}"
run_bounded() {
    local pid watchdog rc=0
    "$@" &
    pid=$!
    ( sleep "$CALL_TIMEOUT_SECS"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid" 2>/dev/null || rc=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return "$rc"
}

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

    LIST_OUTPUT=$(run_bounded jules remote list --session 2>&1 || true)

    for SID in "${SESSIONS[@]}"; do
        # Check if already processed
        if [[ "$COMPLETED_SESSIONS" == *" $SID "* || "$AWAITING_FEEDBACK_SESSIONS" == *" $SID "* || "$FAILED_SESSIONS" == *" $SID "* ]]; then
            continue
        fi

        # Authoritative inspection via jules_api.py
        API_SCRIPT="$SCRIPT_DIR/jules_api.py"
        INSPECT_JSON=""
        if [[ -f "$API_SCRIPT" ]]; then
            INSPECT_JSON=$(run_bounded python3 "$API_SCRIPT" inspect "$SID" --json 2>/dev/null || true)
        fi

        OP_STATUS=""
        IS_INTERACTIVE=false
        IS_SUSPENDED=false
        IS_STALLED=false
        STALL_MINS=0
        HAS_PATCH=false
        PATCH_COUNT=0
        FAIL_MSG=""
        FAIL_TYPE=""
        QUESTION=""
        AUTO_ANSWERABLE=false

        if [[ -n "$INSPECT_JSON" ]]; then
            OP_STATUS=$(echo "$INSPECT_JSON" | grep -o '"task_status": *"[^"]*"' | head -n 1 | sed -E 's/"task_status": *"([^"]*)"/\1/' || true)
            if echo "$INSPECT_JSON" | grep -q '"is_interactive": *true'; then IS_INTERACTIVE=true; fi
            if echo "$INSPECT_JSON" | grep -q '"is_suspended": *true'; then IS_SUSPENDED=true; fi
            if echo "$INSPECT_JSON" | grep -q '"is_stalled": *true'; then IS_STALLED=true; fi
            if echo "$INSPECT_JSON" | grep -q '"has_patch": *true'; then HAS_PATCH=true; fi
            PATCH_COUNT=$(echo "$INSPECT_JSON" | grep -o '"patch_files_count": *[0-9]*' | head -n 1 | grep -o '[0-9]*' || echo "0")
            STALL_MINS=$(echo "$INSPECT_JSON" | grep -o '"stall_minutes": *[0-9]*' | head -n 1 | grep -o '[0-9]*' || echo "0")
            FAIL_MSG=$(echo "$INSPECT_JSON" | grep -o '"failure_message": *"[^"]*"' | head -n 1 | sed -E 's/"failure_message": *"([^"]*)"/\1/' || true)
            FAIL_TYPE=$(echo "$INSPECT_JSON" | grep -o '"failure_type": *"[^"]*"' | head -n 1 | sed -E 's/"failure_type": *"([^"]*)"/\1/' || true)
            QUESTION=$(echo "$INSPECT_JSON" | grep -o '"question": *"[^"]*"' | head -n 1 | sed -E 's/"question": *"([^"]*)"/\1/' || true)
            if echo "$INSPECT_JSON" | grep -q '"auto_answerable": *true'; then AUTO_ANSWERABLE=true; fi
        fi

        # Fallback to scraping jules remote list if API inspection didn't return a status
        STATUS_LINE=$(echo "$LIST_OUTPUT" | grep -E "\b$SID\b" || true)
        if [[ -z "$OP_STATUS" && -n "$STATUS_LINE" ]]; then
            if echo "$STATUS_LINE" | grep -qi "Completed"; then OP_STATUS="COMPLETED"; fi
            if echo "$STATUS_LINE" | grep -qi "Failed"; then OP_STATUS="FAILED"; fi
            if echo "$STATUS_LINE" | grep -qi "Awaiting User"; then IS_INTERACTIVE=true; fi
        fi

        if [[ "$OP_STATUS" == "COMPLETED" ]]; then
            echo "✅ [DONE: Completed] Session $SID finalized remotely."
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            COMPLETED_SESSIONS="${COMPLETED_SESSIONS}${SID} "
        elif [[ "$IS_INTERACTIVE" == "true" ]]; then
            echo "⚡ [INTERACTIVE: Awaiting User Feedback] Session $SID requires user response!"
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            AUTO_RESOLVED=false
            if [[ -x "$API_SCRIPT" && "$INTERACTIVE_MODE" == "true" && "$AUTO_ANSWERABLE" == "true" ]]; then
                echo "   🤖 [--interactive] Evaluating auto-answer heuristics for session $SID..."
                if run_bounded python3 "$API_SCRIPT" auto-answer "$SID" 2>&1; then
                    echo "   ✅ Automatically resolved boilerplate prompt. Resuming token-free watcher..."
                    AUTO_RESOLVED=true
                    sleep 10
                else
                    echo "   ⚡ Prompt is substantive: requires manual or escalated decision."
                fi
            fi

            if [[ "$AUTO_RESOLVED" == "false" && -n "$QUESTION" ]]; then
                echo "   ❓ Jules Question: $QUESTION"
            fi

            if [[ "$AUTO_RESOLVED" == "true" ]]; then
                ALL_DONE=false
            else
                echo "   ⛔ STRICT GUARD: Task is in interactive state. DO NOT MERGE. DO NOT CONSIDER COMPLETED."
                echo "   💡 Action: Use 'jules-gate interact $SID \"<answer>\"' to unblock Jules."
                AWAITING_FEEDBACK_SESSIONS="${AWAITING_FEEDBACK_SESSIONS}${SID} "
            fi
        elif [[ "$OP_STATUS" == "FAILED" ]]; then
            echo "❌ [FAILED] Session $SID failed remotely!"
            if [[ -n "$FAIL_MSG" || -n "$FAIL_TYPE" ]]; then
                echo "   Reason: ${FAIL_TYPE:-ERROR} - ${FAIL_MSG:-Unspecified failure}"
            fi
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            if [[ "$HAS_PATCH" == "true" && "$PATCH_COUNT" -gt 0 ]]; then
                echo "   💡 Work salvageable: Cumulative patch contains changes for $PATCH_COUNT files!"
                echo "      Run 'jules-gate verify $SID <base> --allow-failed' or 'jules remote pull --session $SID' to inspect work."
            fi
            FAILED_SESSIONS="${FAILED_SESSIONS}${SID} "
        elif [[ "$IS_SUSPENDED" == "true" ]]; then
            echo "⚠️  [SUSPENDED] Session $SID DevBox was suspended by cloud backend."
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            if [[ "$HAS_PATCH" == "true" && "$PATCH_COUNT" -gt 0 ]]; then
                echo "   💡 Work salvageable: Cumulative patch contains changes for $PATCH_COUNT files!"
                echo "      Run 'jules-gate verify $SID <base> --allow-failed' to salvage verified work."
            fi
            FAILED_SESSIONS="${FAILED_SESSIONS}${SID} "
        elif [[ "$IS_STALLED" == "true" ]]; then
            echo "⚠️  [STALL DETECTED] Session $SID has shown no activity for $STALL_MINS minutes!"
            echo "   Cloud DevBox may be deadlocked, running heavy dataset compilation, or killed."
            echo "   🌐 Web Session: https://jules.google.com/task/$SID"
            if [[ "$STALL_MINS" -ge 45 ]]; then
                echo "   ⚡ [WATCHDOG AUTO-HALT] Session stalled for >= 45m. Halting watcher to prevent infinite wait."
                FAILED_SESSIONS="${FAILED_SESSIONS}${SID} "
            else
                ALL_DONE=false
            fi
        elif [[ -z "$OP_STATUS" && -z "$STATUS_LINE" ]]; then
            ALL_DONE=false
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
