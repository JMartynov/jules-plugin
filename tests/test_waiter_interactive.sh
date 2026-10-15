#!/usr/bin/env bash
# jules_poll_wait.sh must exit 10 for a session that waits for an answer even if the list status says "Paused".
set -uo pipefail
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PASS=0; FAIL=0
ok(){ echo "  ✅ [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ [FAIL] $1"; FAIL=$((FAIL+1)); }
T=$(mktemp -d /tmp/jules-waiter-XXXXXX); mkdir -p "$T/bin" "$T/scripts"
# The copy under test differs from the real script only in two timing constants (poll 30s -> 1s, auto-answer pause 10s -> 1s,
# and --timeout counted in seconds instead of minutes) so that the suite runs in seconds.
sed -e 's/sleep 30/sleep 1/' -e 's/sleep 10/sleep 1/' -e 's/TIMEOUT_SECS=$((TIMEOUT_MINS \* 60))/TIMEOUT_SECS=$TIMEOUT_MINS/' "$ROOT/scripts/jules_poll_wait.sh" > "$T/scripts/jules_poll_wait.sh"
grep -q 'TIMEOUT_SECS=$TIMEOUT_MINS' "$T/scripts/jules_poll_wait.sh" && grep -q 'sleep 1$' "$T/scripts/jules_poll_wait.sh" || { echo "test harness: sed did not apply"; exit 1; }
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
echo " $FAKE_SID    # Task: x   owner/repo   5s ago   $FAKE_STATUS"
EOS
chmod +x "$T/bin/jules"
stub_api(){ cat > "$T/scripts/jules_api.py" <<EOS
import sys
if sys.argv[1] == "inspect":
    print('{"session_id": "s", "is_interactive": $1, "question": "Is this ok?"}')
    sys.exit(0)
sys.exit(1)   # auto-answer: substantive
EOS
}
run(){ PATH="$T/bin:$PATH" FAKE_SID=123456 FAKE_STATUS="$1" bash "$T/scripts/jules_poll_wait.sh" --interactive --timeout 1 123456 >"$T/out" 2>&1; echo $?; }
stub_api true;  rc=$(run "Paused");      [[ "$rc" == 10 ]] && ok "Paused status + open question -> exit 10" || bad "paused rc=$rc"
stub_api true;  rc=$(run "In Progress"); [[ "$rc" == 10 ]] && ok "In Progress status + open question -> exit 10" || bad "in progress rc=$rc"
stub_api false; rc=$(PATH="$T/bin:$PATH" FAKE_SID=123456 FAKE_STATUS="Completed" bash "$T/scripts/jules_poll_wait.sh" --interactive --timeout 1 123456 >"$T/out" 2>&1; echo $?); [[ "$rc" == 0 ]] && ok "Completed -> exit 0 (inspect not needed)" || bad "completed rc=$rc"
stub_api true;  rc=$(PATH="$T/bin:$PATH" FAKE_SID=123456 FAKE_STATUS="Awaiting User Feedback" bash "$T/scripts/jules_poll_wait.sh" --interactive --timeout 1 123456 >"$T/out" 2>&1; echo $?); [[ "$rc" == 10 ]] && ok "Awaiting User Feedback still -> exit 10" || bad "awaiting rc=$rc"
stub_api false; rc=$(PATH="$T/bin:$PATH" FAKE_SID=123456 FAKE_STATUS="Awaiting User Feedback" bash "$T/scripts/jules_poll_wait.sh" --interactive --timeout 1 123456 >"$T/out" 2>&1; echo $?); [[ "$rc" == 1 ]] && ok "stale Awaiting User Feedback (inspect says answered) keeps waiting -> exit 1" || bad "stale awaiting rc=$rc"


# --- more cases -------------------------------------------------------------------------------
# an answered question (inspect says not interactive) keeps waiting until the timeout (exit 1), no false alarm
stub_api false; rc=$(run "In Progress"); [[ "$rc" == 1 ]] && ok "answered/non-blocking session keeps waiting, times out with exit 1" || bad "answered rc=$rc"
# the inspect call failing must not crash or fake an alarm
cat > "$T/scripts/jules_api.py" <<'EOS'
import sys
sys.stderr.write("boom")
sys.exit(3)
EOS
rc=$(run "In Progress"); [[ "$rc" == 1 ]] && ok "failing inspect is ignored (no crash, no false alarm)" || bad "failing inspect rc=$rc"
printf 'not json at all\n' > /dev/null
cat > "$T/scripts/jules_api.py" <<'EOS'
print("not json")
EOS
rc=$(run "Paused"); [[ "$rc" == 1 ]] && ok "garbage inspect output is ignored" || bad "garbage rc=$rc"
# a failed session exits 2 and inspect is not consulted
cat > "$T/scripts/jules_api.py" <<'EOS'
open("/tmp/jules-waiter-inspect-called", "w").write("x")
print('{"is_interactive": true}')
EOS
rm -f /tmp/jules-waiter-inspect-called
rc=$(run "Failed"); [[ "$rc" == 2 && ! -e /tmp/jules-waiter-inspect-called ]] && ok "Failed -> exit 2 without calling inspect" || bad "failed rc=$rc"
rm -f /tmp/jules-waiter-inspect-called
# the output tells the operator what to do and shows the question
stub_api true; run "Paused" >/dev/null; grep -q "jules-gate interact" "$T/out" && grep -q "STRICT GUARD" "$T/out" && ok "alert output names interact and the merge guard" || bad "alert output incomplete"
# boilerplate question is auto-answered with --interactive and the waiter resumes (stub: auto-answer succeeds, then session completes)
cat > "$T/scripts/jules_api.py" <<'EOS'
import os, sys
flag = "/tmp/jules-waiter-answered"
if sys.argv[1] == "inspect":
    print('{"is_interactive": %s}' % ("false" if os.path.exists(flag) else "true"))
    sys.exit(0)
open(flag, "w").write("x"); sys.exit(0)   # auto-answer succeeds
EOS
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
if [[ -e /tmp/jules-waiter-answered ]]; then echo " 123456  x  r  1s ago  Completed"; else echo " 123456  x  r  1s ago  Paused"; fi
EOS
chmod +x "$T/scripts/jules_api.py"   # the waiter only runs auto-answer when the API script is executable, as installed
rm -f /tmp/jules-waiter-answered
rc=$(PATH="$T/bin:$PATH" bash "$T/scripts/jules_poll_wait.sh" --interactive --timeout 8 123456 >"$T/out" 2>&1; echo $?)
[[ "$rc" == 0 ]] && grep -q "Automatically resolved" "$T/out" && ok "boilerplate question auto-answered, then Completed -> exit 0" || bad "auto-answer flow rc=$rc"
rm -f /tmp/jules-waiter-answered
# two sessions, only the second waits -> exit 10 and the first is not reported as an alarm
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
echo " 111111  x  r  1s ago  Completed"
echo " 222222  x  r  1s ago  Paused"
EOS
cat > "$T/scripts/jules_api.py" <<'EOS'
import sys
sid = sys.argv[2]
print('{"is_interactive": %s, "question": "q"}' % ("true" if sid == "222222" else "false"))
EOS
rc=$(PATH="$T/bin:$PATH" bash "$T/scripts/jules_poll_wait.sh" --timeout 1 111111 222222 >"$T/out" 2>&1; echo $?)
[[ "$rc" == 10 ]] && grep -q "Session 222222 requires" "$T/out" && ! grep -q "Session 111111 requires" "$T/out" && ok "two sessions: only the waiting one raises the alarm (exit 10)" || bad "two sessions rc=$rc"
# a hung inspect call or a hung `jules remote list` must be killed (JULES_CALL_TIMEOUT) so the watcher keeps polling and still honours --timeout
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
echo " 123456  x  r  1s ago  In Progress"
EOS
cat > "$T/scripts/jules_api.py" <<'EOS'
import time
time.sleep(300)
EOS
t0=$(date +%s); rc=$(JULES_CALL_TIMEOUT=2 PATH="$T/bin:$PATH" bash "$T/scripts/jules_poll_wait.sh" --interactive --timeout 6 123456 >"$T/out" 2>&1 & p=$!; for _ in $(seq 1 40); do kill -0 $p 2>/dev/null || break; sleep 1; done; if kill -0 $p 2>/dev/null; then kill $p; echo hung; else wait $p; echo $?; fi); el=$(( $(date +%s) - t0 ))
[[ "$rc" == 1 ]] && ok "hung inspect is killed; watcher times out normally (exit 1, ${el}s)" || bad "hung inspect rc=$rc (${el}s)"
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
exec sleep 300
EOS
t0=$(date +%s); rc=$(JULES_CALL_TIMEOUT=2 PATH="$T/bin:$PATH" bash "$T/scripts/jules_poll_wait.sh" --timeout 6 123456 >"$T/out" 2>&1 & p=$!; for _ in $(seq 1 40); do kill -0 $p 2>/dev/null || break; sleep 1; done; if kill -0 $p 2>/dev/null; then kill $p; echo hung; else wait $p; echo $?; fi); el=$(( $(date +%s) - t0 ))
[[ "$rc" == 1 ]] && ok "hung 'jules remote list' is killed; watcher times out normally (exit 1, ${el}s)" || bad "hung list rc=$rc (${el}s)"
rm -rf "$T"; echo " Passed: $PASS  Failed: $FAIL"; [[ $FAIL -eq 0 ]]
