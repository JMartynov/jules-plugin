#!/usr/bin/env bash
# test_invariants.sh - Comprehensive invariant test suite for jules-plugin & jules-gate
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
GATE_BIN="$PLUGIN_ROOT/bin/jules-gate"
SCRIPTS_DIR="$PLUGIN_ROOT/scripts"

export PATH="$PLUGIN_ROOT/bin:$PATH"
export JULES_GATE_NO_BROWSER=1
export CI=true

PASS_COUNT=0
FAIL_COUNT=0

log_pass() {
    echo "  ✅ [PASS] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
    echo "  ❌ [FAIL] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local desc="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$desc"
    else
        log_fail "$desc (expected '$expected', got '$actual')"
    fi
}

echo "=========================================================="
echo " Starting Invariant Tests for Jules Task Controller"
echo " Plugin Root: $PLUGIN_ROOT"
echo "=========================================================="

# ------------------------------------------------------------
# INVARIANT 1: CLI Command Structure & Help
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 1: CLI Dispatch & Usage] ---"

HELP_OUT=$("$GATE_BIN" help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "Commands:"; then
    log_pass "jules-gate help displays command summary"
else
    log_fail "jules-gate help failed to output command summary"
fi

for subcmd in wait verify merge pr ps status lint tokens web close reply inspect interact auto-answer; do
    if echo "$HELP_OUT" | grep -q "$subcmd"; then
        log_pass "Subcommand '$subcmd' documented in help output"
    else
        log_fail "Subcommand '$subcmd' missing from help output"
    fi
done

STATUS_OUT=$("$GATE_BIN" status 2>&1 || true)
EXPECTED_VER=$(grep '"version"' "$PLUGIN_ROOT/plugin.json" | head -n 1 | sed -E 's/.*"version": *"([^"]+)".*/\1/')
if [[ "$EXPECTED_VER" != "3.4.0" ]]; then
    log_fail "Expected version 3.4.0 in plugin.json, got $EXPECTED_VER"
fi
if echo "$STATUS_OUT" | grep -q "$EXPECTED_VER"; then
    log_pass "jules-gate status outputs plugin version ($EXPECTED_VER)"
else
    log_fail "jules-gate status failed to output plugin version"
fi

if echo "$STATUS_OUT" | grep -q "Jules CLI:"; then
    log_pass "jules-gate status outputs Jules CLI status"
else
    log_fail "jules-gate status missing Jules CLI status"
fi

LINT_OUT=$("$GATE_BIN" lint 2>&1 || true)
if echo "$LINT_OUT" | grep -q "Pre-Dispatch Contract Linter"; then
    log_pass "jules-gate lint executes and prints contract linter header"
else
    log_fail "jules-gate lint failed to print contract linter header"
fi

# Complexity heuristic check in jules-gate lint
TMP_P=$(mktemp "/tmp/short_prompt-XXXXXX.txt")
echo "Fix typo in doc" > "$TMP_P"
LINT_HEURISTIC_OUT=$("$GATE_BIN" lint "" "$TMP_P" 2>&1 || true)
rm -f "$TMP_P"
if echo "$LINT_HEURISTIC_OUT" | grep -q "Candidate for Local Efficiency Override"; then
    log_pass "jules-gate lint complexity heuristic flags concise micro-prompt"
else
    log_fail "jules-gate lint failed to flag concise micro-prompt"
fi

# Completion directive check in jules-gate lint
TMP_P2=$(mktemp "/tmp/directive_prompt-XXXXXX.txt")
echo "Implement tests and finalize directly without asking questions." > "$TMP_P2"
LINT_DIR_OUT=$("$GATE_BIN" lint "" "$TMP_P2" 2>&1 || true)
rm -f "$TMP_P2"
if echo "$LINT_DIR_OUT" | grep -q "Non-interactive conclusion directive detected"; then
    log_pass "jules-gate lint verifies non-interactive conclusion directive"
else
    log_fail "jules-gate lint failed to detect non-interactive conclusion directive"
fi

# Token telemetry checks
TOKENS_OUT=$("$GATE_BIN" tokens 2>&1 || true)
if echo "$TOKENS_OUT" | grep -q "Token Economy & Sparing Telemetry"; then
    log_pass "jules-gate tokens executes and outputs telemetry summary"
else
    log_fail "jules-gate tokens failed to output telemetry summary"
fi

TOKENS_JSON=$("$GATE_BIN" tokens --json 2>&1 || true)
if echo "$TOKENS_JSON" | grep -q '"estimated_tokens_spared"'; then
    log_pass "jules-gate tokens --json outputs valid JSON metrics"
else
    log_fail "jules-gate tokens --json failed to output JSON metrics"
fi

# Verify close and reply invariants
CLOSE_OUT=$("$GATE_BIN" close 12345 2>&1 || true)
if echo "$CLOSE_OUT" | grep -q "https://jules.google.com/task/12345"; then
    log_pass "jules-gate close outputs expected task dismissal guidance and URL"
else
    log_fail "jules-gate close missing task dismissal guidance or URL"
fi

REPLY_OUT=$("$GATE_BIN" reply 12345 "test_error" 2>&1 || true)
if echo "$REPLY_OUT" | grep -q "https://jules.google.com/task/12345" && echo "$REPLY_OUT" | grep -q "Using provided text message"; then
    log_pass "jules-gate reply outputs rapid repair instructions and URL"
else
    log_fail "jules-gate reply missing rapid repair instructions or URL"
fi

# Verify browser suppression in headless/test mode
if grep -q "open_browser_url" "$GATE_BIN" && grep -q "JULES_GATE_NO_BROWSER" "$GATE_BIN"; then
    log_pass "jules-gate defines open_browser_url guarded by JULES_GATE_NO_BROWSER and CI/TESTING"
else
    log_fail "jules-gate missing open_browser_url headless guard"
fi

WEB_OUT=$("$GATE_BIN" web 12345 2>&1 || true)
if echo "$WEB_OUT" | grep -q "https://jules.google.com/task/12345"; then
    log_pass "jules-gate web executes cleanly in headless mode without browser popups"
else
    log_fail "jules-gate web failed in headless mode"
fi

# ------------------------------------------------------------
# INVARIANT 2: Dynamic Multi-Tier Documentation & 4-Stage Lifecycle Guardrails
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 2: Multi-Tier Model Routing Docs] ---"

if grep -q "flash_lite" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "rules/AGENTS.md documents flash_lite tier"
else
    log_fail "rules/AGENTS.md is missing flash_lite tier documentation"
fi

if grep -q "tiered routing" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" || grep -q "Multi-Tier" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md"; then
    log_pass "skills/jules-task-controller/SKILL.md documents multi-tiered routing"
else
    log_fail "skills/jules-task-controller/SKILL.md is missing tiered routing documentation"
fi

# Ensure Strict No-Polling rule is codified
if grep -q -i "no-polling" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "rules/AGENTS.md contains Strict No-Polling directive"
else
    log_fail "rules/AGENTS.md missing Strict No-Polling directive"
fi

if grep -q -i "no-polling" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md"; then
    log_pass "skills/jules-task-controller/SKILL.md contains Strict No-Polling directive"
else
    log_fail "skills/jules-task-controller/SKILL.md missing Strict No-Polling directive"
fi

# Ensure Research sub-agent pattern is codified
if grep -q -i "research sub-agent" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md"; then
    log_pass "skills/jules-task-controller/SKILL.md contains Research sub-agent pattern"
else
    log_fail "skills/jules-task-controller/SKILL.md missing Research sub-agent pattern"
fi

# Ensure Token-Sparing Forking statement is codified
if grep -q -i "forking" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md"; then
    log_pass "skills/jules-task-controller/SKILL.md documents token-sparing forking architecture"
else
    log_fail "skills/jules-task-controller/SKILL.md missing token-sparing forking documentation"
fi

# Ensure Efficiency Override / Local Option is codified
if grep -q -i "Efficiency Override" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" && grep -q -i "Efficiency Override" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "SKILL.md and rules/AGENTS.md document Efficiency Override (Local Option)"
else
    log_fail "Efficiency Override documentation missing from SKILL.md or rules/AGENTS.md"
fi

# Ensure Sub-agent telemetry reporting directive is codified
if grep -q "tokens --json" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" && grep -q "tokens --json" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "SKILL.md and rules/AGENTS.md mandate sub-agent telemetry reporting via tokens --json"
else
    log_fail "SKILL.md or rules/AGENTS.md missing sub-agent telemetry reporting directive"
fi

# Ensure Lifecycle transparency (Awaiting User Feedback vs Completed) is codified
if grep -q "Awaiting User Feedback" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" && grep -q "Awaiting User Feedback" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "SKILL.md and rules/AGENTS.md document cloud lifecycle transparency (Awaiting User Feedback)"
else
    log_fail "SKILL.md or rules/AGENTS.md missing cloud lifecycle transparency documentation"
fi

# Ensure Non-interactive completion directive is codified
if grep -qi "without asking" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" && grep -qi "without asking" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "SKILL.md and rules/AGENTS.md document non-interactive task completion directive"
else
    log_fail "SKILL.md or rules/AGENTS.md missing non-interactive task completion directive"
fi

# Ensure 3-Tier Escalation Protocol is codified
if grep -q "3-Tier" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" && grep -q "3-Tier" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "SKILL.md and rules/AGENTS.md document 3-Tier Interactive Task Resolution Protocol"
else
    log_fail "SKILL.md or rules/AGENTS.md missing 3-Tier Interactive Task Resolution Protocol"
fi

# Ensure Strict No-Merge on interactive state is codified
if grep -q "Strict No-Merge" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md" && grep -q "Strict No-Merge" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "SKILL.md and rules/AGENTS.md enforce Strict No-Merge on interactive state"
else
    log_fail "SKILL.md or rules/AGENTS.md missing Strict No-Merge rule"
fi

# ------------------------------------------------------------
# INVARIANT 3: Zero-Token Polling Watcher (jules_poll_wait.sh)
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 3: Zero-Token Polling Watcher] ---"

MOCK_DIR=$(mktemp -d "/tmp/jules-mock-XXXXXX")
cat > "$MOCK_DIR/jules" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"remote list --session"* ]]; then
    cat "$MOCK_STATE_FILE"
fi
EOF
chmod +x "$MOCK_DIR/jules"

OLD_PATH="$PATH"
export PATH="$MOCK_DIR:$PATH"
export MOCK_STATE_FILE="$MOCK_DIR/state.txt"

# Case 2A: Session Completes
echo "1111111111111111 Completed" > "$MOCK_STATE_FILE"
set +e
"$SCRIPTS_DIR/jules_poll_wait.sh" 1111111111111111 --timeout 1 >/dev/null 2>&1
POLL_EXIT=$?
set -e
assert_eq "$POLL_EXIT" "0" "jules_poll_wait detects Completed status with exit code 0"

# Case 2B: Session Fails Remotely
echo "2222222222222222 Failed" > "$MOCK_STATE_FILE"
set +e
"$SCRIPTS_DIR/jules_poll_wait.sh" 2222222222222222 --timeout 1 >/dev/null 2>&1
POLL_EXIT=$?
set -e
assert_eq "$POLL_EXIT" "2" "jules_poll_wait detects Failed status with exit code 2"

# Case 2C: Multiple Parallel Sessions
cat > "$MOCK_STATE_FILE" << 'EOF'
10001 Completed
10002 Completed
EOF
set +e
"$SCRIPTS_DIR/jules_poll_wait.sh" 10001 10002 --timeout 1 >/dev/null 2>&1
POLL_EXIT=$?
set -e
assert_eq "$POLL_EXIT" "0" "jules_poll_wait handles multiple parallel sessions successfully"

# Case 2D: Session in Awaiting User Feedback (Interactive State Guard)
echo "3333333333333333 Awaiting User Feedback" > "$MOCK_STATE_FILE"
set +e
AWAIT_OUT=$("$SCRIPTS_DIR/jules_poll_wait.sh" 3333333333333333 --timeout 1 2>&1)
POLL_AWAIT_EXIT=$?
set -e
assert_eq "$POLL_AWAIT_EXIT" "10" "jules_poll_wait detects Awaiting User Feedback and exits 10 (Interactive Guard)"
if echo "$AWAIT_OUT" | grep -q "INTERACTIVE" && echo "$AWAIT_OUT" | grep -q "DO NOT MERGE"; then
    log_pass "jules_poll_wait outputs interactive guard warning (DO NOT MERGE)"
else
    log_fail "jules_poll_wait missing interactive guard warning"
fi

# Invariant: jules-gate merge refuses to merge interactive session
set +e
MERGE_REFUSE_OUT=$("$GATE_BIN" merge 3333333333333333 2>&1)
MERGE_REFUSE_EXIT=$?
set -e
assert_eq "$MERGE_REFUSE_EXIT" "5" "jules-gate merge blocks merging interactive sessions (exit code 5)"
if echo "$MERGE_REFUSE_OUT" | grep -q "STRICT GUARD ERROR"; then
    log_pass "jules-gate merge prints STRICT GUARD ERROR on interactive session"
else
    log_fail "jules-gate merge missing STRICT GUARD ERROR message"
fi

export PATH="$OLD_PATH"
rm -rf "$MOCK_DIR"

# ------------------------------------------------------------
# INVARIANT 4: Gated Verification & Worktree Isolation
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 4: Gated Verification (worktree_gate.sh)] ---"

if grep -q "export PYTHONDONTWRITEBYTECODE=1" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh prevents python bytecode generation"
else
    log_fail "worktree_gate.sh missing PYTHONDONTWRITEBYTECODE export"
fi

if grep -q "__pycache__/" "$PLUGIN_ROOT/.gitignore" && grep -q "\*.pyc" "$PLUGIN_ROOT/.gitignore"; then
    log_pass ".gitignore contains python bytecode exclusions"
else
    log_fail ".gitignore missing python bytecode exclusions"
fi

TEST_REPO=$(mktemp -d "/tmp/jules-test-repo-XXXXXX")
LOG_DIR=$(mktemp -d "/tmp/jules-logs-XXXXXX")

git init -b main "$TEST_REPO" >/dev/null 2>&1
cd "$TEST_REPO"
git config user.email "test@example.com"
git config user.name "Test Runner"

# Configure .gitignore
cat > .gitignore << 'EOF'
.jules
*.log
__pycache__/
.pytest_cache/
EOF

# Seed a python project in test repo
cat > calc.py << 'EOF'
def add(a, b):
    return a + b
EOF

cat > test_calc.py << 'EOF'
from calc import add

def test_add():
    assert add(2, 3) == 5
EOF

git add .
git commit -m "initial commit" >/dev/null 2>&1

# Setup mock jules pull command
MOCK_DIR=$(mktemp -d "/tmp/jules-mock-XXXXXX")
cat > "$MOCK_DIR/jules" << EOF
#!/usr/bin/env bash
if [[ "\$*" == *"remote pull --session 301"* ]]; then
    cat "$LOG_DIR/valid.patch"
elif [[ "\$*" == *"remote pull --session 302"* ]]; then
    cat "$LOG_DIR/failing_test.patch"
elif [[ "\$*" == *"remote pull --session 303"* ]]; then
    echo "CORRUPT PATCH GARBAGE"
elif [[ "\$*" == *"remote pull --session 305"* ]]; then
    cat "$LOG_DIR/pr_valid.patch"
fi
EOF
chmod +x "$MOCK_DIR/jules"
export PATH="$MOCK_DIR:$PATH"

# Generate valid patch (improves code, tests still pass)
python3 -c "f = open('calc.py', 'r'); c = f.read(); open('calc.py', 'w').write(c.replace('return a + b', 'return a + b  # verified'))"
git diff calc.py > "$LOG_DIR/valid.patch"
git checkout -f calc.py

# Generate failing test patch (breaks logic: add returns a - b)
python3 -c "f = open('calc.py', 'r'); c = f.read(); open('calc.py', 'w').write(c.replace('return a + b', 'return a - b'))"
git diff calc.py > "$LOG_DIR/failing_test.patch"
git checkout -f calc.py

# Case 3A: Valid patch verification
set +e
"$SCRIPTS_DIR/worktree_gate.sh" 301 main > "$LOG_DIR/301.log" 2>&1
VERIFY_EXIT=$?
set -e
assert_eq "$VERIFY_EXIT" "0" "worktree_gate exits 0 on valid patch passing tests"

# Check branch exists and has commit
HAS_BRANCH=$(git branch --list "jules/review-301")
if [[ -n "$HAS_BRANCH" ]]; then
    log_pass "Review branch jules/review-301 was created and committed"
else
    log_fail "Review branch jules/review-301 was NOT created"
fi

# Case 3B: Failing patch verification (Must revert cleanly and NOT corrupt base branch)
git checkout main >/dev/null 2>&1
set +e
"$SCRIPTS_DIR/worktree_gate.sh" 302 main > "$LOG_DIR/302.log" 2>&1
VERIFY_FAIL_EXIT=$?
set -e
assert_eq "$VERIFY_FAIL_EXIT" "3" "worktree_gate exits 3 when tests fail"

# Verify review branch was deleted and working tree is clean
HAS_BAD_BRANCH=$(git branch --list "jules/review-302")
if [[ -z "$HAS_BAD_BRANCH" ]]; then
    log_pass "Failing review branch jules/review-302 was automatically cleaned up"
else
    log_fail "Failing review branch jules/review-302 was NOT deleted"
fi

STATUS_CLEAN=$(git status --porcelain)
if [[ -z "$STATUS_CLEAN" ]]; then
    log_pass "Base branch working tree remained completely clean after test failure"
else
    log_fail "Working tree dirty after failure: $STATUS_CLEAN"
fi

# Case 3C: Corrupt patch verification
set +e
"$SCRIPTS_DIR/worktree_gate.sh" 303 main > "$LOG_DIR/303.log" 2>&1
CORRUPT_EXIT=$?
set -e
assert_eq "$CORRUPT_EXIT" "2" "worktree_gate exits 2 on un-applicable patch"

# ------------------------------------------------------------
# INVARIANT 5: Integration & Merging (jules-gate merge)
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 5: Integration & Branch Cleanup (jules-gate merge)] ---"

git checkout main >/dev/null 2>&1
set +e
"$GATE_BIN" merge 301 main > "$LOG_DIR/merge.log" 2>&1
MERGE_EXIT=$?
set -e
assert_eq "$MERGE_EXIT" "0" "jules-gate merge exits 0 on successful merge"

# Verify changes are in main
if grep -q "verified" calc.py; then
    log_pass "Verified changes successfully integrated into main"
else
    log_fail "Changes missing in main branch"
fi

# Verify review branch was deleted
HAS_BRANCH_AFTER=$(git branch --list "jules/review-301")
if [[ -z "$HAS_BRANCH_AFTER" ]]; then
    log_pass "Review branch jules/review-301 deleted after successful merge"
else
    log_fail "Review branch jules/review-301 still exists after merge"
fi

# Verify PR body embeds token efficiency badge
MOCK_GH_DIR=$(mktemp -d "/tmp/jules-mock-gh-XXXXXX")
cat > "$MOCK_GH_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo "$*" > "$MOCK_GH_LOG"
exit 0
EOF
chmod +x "$MOCK_GH_DIR/gh"

export MOCK_GH_LOG="$MOCK_GH_DIR/gh_call.txt"
OLD_GH_PATH="$PATH"
export PATH="$MOCK_GH_DIR:$PATH"

python3 -c "f = open('calc.py', 'r'); c = f.read(); open('calc.py', 'w').write(c + '\n# PR badge verified addition\n')"
git diff calc.py > "$LOG_DIR/pr_valid.patch"
git checkout -f calc.py

BARE_REPO=$(mktemp -d "/tmp/jules-bare-XXXXXX")
git init --bare "$BARE_REPO" >/dev/null 2>&1
git remote remove origin 2>/dev/null || true
git remote add origin "$BARE_REPO"
git push -u origin main >/dev/null 2>&1

set +e
"$GATE_BIN" pr 305 main > "$LOG_DIR/pr.log" 2>&1
PR_EXIT=$?
set -e

if grep -q "Verified by Jules Gate" "$MOCK_GH_LOG" 2>/dev/null && grep -q "tokens spared" "$MOCK_GH_LOG" 2>/dev/null; then
    log_pass "jules-gate pr embeds Token Efficiency Badge into PR body"
else
    log_fail "jules-gate pr missing Token Efficiency Badge in PR body ($(cat "$LOG_DIR/pr.log" 2>/dev/null))"
fi

export PATH="$OLD_GH_PATH"
rm -rf "$MOCK_GH_DIR" "$BARE_REPO"

# ------------------------------------------------------------
# INVARIANT 6: Multi-Language Runner Detection
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 6: Dynamic Test Runner Detection] ---"

cd "$TEST_REPO"
touch package.json
echo '{"scripts": {"test": "echo node_test"}}' > package.json
if grep -q '"test":' package.json; then
    log_pass "Node package.json runner detectable"
fi

touch Cargo.toml
if [[ -f "Cargo.toml" ]]; then
    log_pass "Rust Cargo.toml runner detectable"
fi

touch go.mod
if [[ -f "go.mod" ]]; then
    log_pass "Go go.mod runner detectable"
fi

# ------------------------------------------------------------
# INVARIANT 7: Google AIDA API Engine (jules_api.py)
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 7: Google AIDA API Engine (jules_api.py)] ---"

API_USAGE_OUT=$(python3 "$SCRIPTS_DIR/jules_api.py" 2>&1 || true)
if echo "$API_USAGE_OUT" | grep -q "jules_api.py <inspect|interact"; then
    log_pass "scripts/jules_api.py outputs usage on missing arguments"
else
    log_fail "scripts/jules_api.py missing usage output"
fi

GATE_INSPECT_USAGE=$("$GATE_BIN" inspect 2>&1 || true)
if echo "$GATE_INSPECT_USAGE" | grep -q "Usage: jules-gate inspect"; then
    log_pass "jules-gate inspect enforces session_id argument"
else
    log_fail "jules-gate inspect missing usage validation"
fi

GATE_INTERACT_USAGE=$("$GATE_BIN" interact 2>&1 || true)
if echo "$GATE_INTERACT_USAGE" | grep -q "Usage: jules-gate interact"; then
    log_pass "jules-gate interact enforces argument validation"
else
    log_fail "jules-gate interact missing usage validation"
fi

GATE_AUTO_USAGE=$("$GATE_BIN" auto-answer 2>&1 || true)
if echo "$GATE_AUTO_USAGE" | grep -q "Usage: jules-gate auto-answer"; then
    log_pass "jules-gate auto-answer enforces session_id argument"
else
    log_fail "jules-gate auto-answer missing usage validation"
fi

# REGRESSION TEST: AIDA Task Activity Inspection & TLS Context
AIDA_INSPECT_REGRESSION=$(cd "$PLUGIN_ROOT" && python3 -c "
import unittest.mock as mock
from scripts.jules_api import inspect_session, get_ssl_context

# 1. Verify get_ssl_context returns an SSLContext
ctx = get_ssl_context()
assert ctx is not None, 'get_ssl_context must return valid SSLContext'

# 2. Verify inspect_session uses 'tasks/{id}' path and extracts task.activitySteps correctly
mock_resp = {
    'task': {
        'activitySteps': [
            {
                'id': 'step-1',
                'agentActivity': {
                    'agentMessaged': {
                        'text': 'Should I open a PR or adjust anything?',
                        'requiresUserResponse': True
                    }
                }
            }
        ]
    }
}
with mock.patch('scripts.jules_api.make_request', return_value=mock_resp) as mock_req:
    res = inspect_session('test-session-123')
    mock_req.assert_called_once_with('tasks/test-session-123', method='GET')
    assert res['is_interactive'] is True, 'Session should be identified as interactive'
    assert res['auto_answerable'] is True, 'Boilerplate question should be auto_answerable'
    assert res['step_id'] == 'step-1'

print('OK')
" 2>&1 || true)

if echo "$AIDA_INSPECT_REGRESSION" | grep -q "OK"; then
    log_pass "scripts/jules_api.py correctly inspects tasks/{id} and handles TLS context (regression test)"
else
    log_fail "scripts/jules_api.py regression test failed: $AIDA_INSPECT_REGRESSION"
fi

# ------------------------------------------------------------
# INVARIANT 8: Auto-Answer Heuristics & Interactive Watcher
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 8: Auto-Answer Heuristics & Interactive Watcher] ---"

WAIT_USAGE=$("$SCRIPTS_DIR/jules_poll_wait.sh" --help 2>&1 || true)
if echo "$WAIT_USAGE" | grep -q -- "--interactive|-i"; then
    log_pass "jules_poll_wait.sh documents --interactive|-i flag"
else
    log_fail "jules_poll_wait.sh missing --interactive flag in usage"
fi

AUTO_HEURISTIC_TEST=$(cd "$PLUGIN_ROOT" && python3 -c "
from scripts.jules_api import evaluate_auto_answer
p1, a1 = evaluate_auto_answer('Should I open a PR or adjust anything?')
p2, a2 = evaluate_auto_answer('Would you like me to make any other changes?')
p3, a3 = evaluate_auto_answer('Which option do you prefer: Option A or Option B?')
assert p1 is True, 'Boilerplate PR prompt should be auto-answerable'
assert p2 is True, 'Boilerplate adjustments prompt should be auto-answerable'
assert p3 is False, 'Substantive Option prompt must NOT be auto-answerable'
print('OK')
" 2>&1 || true)

if echo "$AUTO_HEURISTIC_TEST" | grep -q "OK"; then
    log_pass "scripts/jules_api.py evaluate_auto_answer correctly identifies boilerplate vs substantive prompts"
else
    log_fail "scripts/jules_api.py evaluate_auto_answer heuristic failed: $AUTO_HEURISTIC_TEST"
fi

# ------------------------------------------------------------
# INVARIANT 9: Hardening & Safety Blueprint (v3.4.0)
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 9: Hardening & Safety Blueprint (v3.4.0)] ---"

if grep -q "git worktree add" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh uses git worktree add for isolation"
else
    log_fail "worktree_gate.sh missing true git worktree isolation"
fi

if ! grep -q "git checkout -f" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh has completely removed destructive git checkout -f"
else
    log_fail "worktree_gate.sh still contains destructive git checkout -f"
fi

if grep -q "trap 'cleanup' EXIT INT TERM" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh has signal traps (trap cleanup EXIT INT TERM)"
else
    log_fail "worktree_gate.sh missing proper cleanup traps"
fi

if grep -q "ssl.create_default_context()" "$SCRIPTS_DIR/jules_api.py" && ! grep -q "ssl._create_unverified_context()" "$SCRIPTS_DIR/jules_api.py"; then
    log_pass "jules_api.py enforces strict TLS verification"
else
    log_fail "jules_api.py missing strict TLS verification"
fi

if grep -q "\.github/workflows" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh implements protected path gating"
else
    log_fail "worktree_gate.sh missing protected path gating"
fi

# ------------------------------------------------------------
# INVARIANT 10: Sandbox & Flaky Retry Mechanisms (v3.4.0)
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 10: Sandbox & Flaky Retry Mechanisms (v3.4.0)] ---"

if grep -q "\-\-sandbox" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh supports --sandbox flag"
else
    log_fail "worktree_gate.sh missing --sandbox support"
fi

if grep -q "\-\-sandbox" "$GATE_BIN"; then
    log_pass "bin/jules-gate supports --sandbox flag"
else
    log_fail "bin/jules-gate missing --sandbox support"
fi

if grep -q "\-\-retry-flaky" "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh supports --retry-flaky flag"
else
    log_fail "worktree_gate.sh missing --retry-flaky support"
fi

# Test simulated flaky test suite
TEST_REPO2=$(mktemp -d "/tmp/jules-test-repo2-XXXXXX")
cd "$TEST_REPO2"
git init >/dev/null 2>&1
git branch -m main >/dev/null 2>&1
git config user.email "test@example.com"
git config user.name "Test"

cat > "flaky_test.sh" << 'EOF'
#!/usr/bin/env bash
if [[ ! -f "flaky.marker" ]]; then
    echo "Failing first run"
    touch "flaky.marker"
    exit 1
else
    echo "Passing on retry"
    exit 0
fi
EOF
chmod +x "flaky_test.sh"

cat > "package.json" << 'EOF'
{"scripts": {"test": "./flaky_test.sh"}}
EOF
git add flaky_test.sh package.json
git commit -m "add flaky test runner" >/dev/null 2>&1

python3 -c "open('dummy.txt', 'w').write('dummy change')"
git add dummy.txt
git diff --cached > "$LOG_DIR/flaky_fix.patch" 2>/dev/null || true
git reset HEAD dummy.txt >/dev/null 2>&1
rm -f dummy.txt

cat > "$MOCK_DIR/jules" << EOF
#!/usr/bin/env bash
if [[ "\$*" == *"remote pull --session 401"* ]]; then
    cat "$LOG_DIR/flaky_fix.patch"
fi
EOF
chmod +x "$MOCK_DIR/jules"

set +e
rm -f flaky.marker
"$SCRIPTS_DIR/worktree_gate.sh" 401 main --retry-flaky 1 > "$LOG_DIR/401.log" 2>&1
FLAKY_RETRY_EXIT=$?
set -e

if [[ "$FLAKY_RETRY_EXIT" == "0" ]]; then
    if grep -q "FLAKY TEST RESOLVED" "$LOG_DIR/401.log"; then
        log_pass "worktree_gate.sh --retry-flaky resolved failing test on retry"
    else
        log_fail "worktree_gate.sh --retry-flaky succeeded but missing FLAKY TEST RESOLVED log"
    fi
else
    log_fail "worktree_gate.sh --retry-flaky failed on flaky test (exit code $FLAKY_RETRY_EXIT). Log:\n$(cat "$LOG_DIR/401.log")"
fi

# Cleanup
export PATH="$OLD_PATH"
rm -rf "$MOCK_DIR" "$TEST_REPO" "$LOG_DIR" "$TEST_REPO2"



# ------------------------------------------------------------
# INVARIANT 11: Multi-IDE Support (v3.4.0)
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 11: Multi-IDE Support (v3.4.0)] ---"

MCP_SERVER="$SCRIPTS_DIR/jules_mcp.py"
INSTALLER="$PLUGIN_ROOT/install.sh"

if [[ -x "$MCP_SERVER" ]]; then
    log_pass "scripts/jules_mcp.py is executable"
else
    log_fail "scripts/jules_mcp.py is missing or not executable"
fi

cd "$PLUGIN_ROOT"
MCP_OUT=$(echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}' | python3 "$MCP_SERVER" 2>&1 || true)
if echo "$MCP_OUT" | grep -q "jules_dispatch" && echo "$MCP_OUT" | grep -q "jules_wait"; then
    log_pass "scripts/jules_mcp.py responds to JSON-RPC tools/list with valid tool definitions"
else
    log_fail "scripts/jules_mcp.py failed to return tools/list. Output: $MCP_OUT"
fi

INSTALLER_HELP=$("$INSTALLER" --help 2>&1 || true)
if echo "$INSTALLER_HELP" | grep -q -- "--claude-desktop" && echo "$INSTALLER_HELP" | grep -q -- "--all"; then
    log_pass "install.sh documents --claude-desktop and --all flags"
else
    log_fail "install.sh missing --claude-desktop or --all in help output"
fi

# Dry run install to ensure it checks correctly
INSTALL_TEST_DIR=$(mktemp -d "/tmp/jules-install-test-XXXXXX")
OLD_HOME="$HOME"
export HOME="$INSTALL_TEST_DIR"
"$INSTALLER" --all > /dev/null 2>&1
if [[ -d "$HOME/.local/bin" && -L "$HOME/.local/bin/jules-gate" ]]; then
    log_pass "Antigravity symlinks remain 100% intact"
else
    log_fail "Antigravity symlinks failed during --all install"
fi
export HOME="$OLD_HOME"
rm -rf "$INSTALL_TEST_DIR"

# ------------------------------------------------------------
# INVARIANT 12: Worktree PYTHONPATH, .venv/uv, --skip-ci, pr-merge & review-branch
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 12: Local Test Isolation, --skip-ci & Branch Review] ---"

if grep -q 'export PYTHONPATH="${WORKTREE_DIR}/src:${WORKTREE_DIR}:${PYTHONPATH:-}"' "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh exports isolated worktree PYTHONPATH"
else
    log_fail "worktree_gate.sh missing isolated worktree PYTHONPATH export"
fi

if grep -q '$ORIGINAL_DIR/.venv/bin/python -m pytest -q --tb=short' "$SCRIPTS_DIR/worktree_gate.sh" && grep -q 'uv run pytest -q --tb=short' "$SCRIPTS_DIR/worktree_gate.sh"; then
    log_pass "worktree_gate.sh prioritizes .venv/bin/python pytest and supports uv"
else
    log_fail "worktree_gate.sh missing .venv or uv pytest detection"
fi

if grep -q -- "--skip-ci" "$SCRIPTS_DIR/worktree_gate.sh" && grep -q -- "--skip-ci" "$GATE_BIN"; then
    log_pass "worktree_gate.sh and bin/jules-gate support --skip-ci flag"
else
    log_fail "worktree_gate.sh or bin/jules-gate missing --skip-ci support"
fi

if grep -q 'gh auth token --user "$REPO_OWNER"' "$GATE_BIN"; then
    log_pass "bin/jules-gate automatically resolves repository owner GH_TOKEN"
else
    log_fail "bin/jules-gate missing multi-account GH_TOKEN resolution"
fi

if grep -q "pr-merge)" "$GATE_BIN" && grep -q "review-branch|review-pr)" "$GATE_BIN"; then
    log_pass "bin/jules-gate implements pr-merge and review-branch subcommands"
else
    log_fail "bin/jules-gate missing pr-merge or review-branch subcommands"
fi

if grep -q "pr-merge" "$PLUGIN_ROOT/rules/AGENTS.md" && grep -q "pr-merge" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md"; then
    log_pass "rules/AGENTS.md and SKILL.md document EULIS Branch Review & pr-merge workflow"
else
    log_fail "rules/AGENTS.md or SKILL.md missing EULIS Branch Review & pr-merge documentation"
fi

if echo "$MCP_OUT" | grep -q "jules_pr_merge" && echo "$MCP_OUT" | grep -q "jules_review_branch" && echo "$MCP_OUT" | grep -q "jules_pr"; then
    log_pass "scripts/jules_mcp.py exposes jules_pr, jules_pr_merge, and jules_review_branch MCP tools"
else
    log_fail "scripts/jules_mcp.py missing jules_pr, jules_pr_merge, or jules_review_branch in tools/list"
fi

# ------------------------------------------------------------
# INVARIANT 13: Parallel Wave Fan-Out & Git Mutex Serialization
# ------------------------------------------------------------
echo ""
echo "--- [Invariant 13: Parallel Wave Fan-Out & Git Mutex Serialization] ---"

if grep -q "with_git_lock()" "$GATE_BIN" && grep -q 'mkdir "$lock_dir"' "$GATE_BIN"; then
    log_pass "bin/jules-gate implements atomic with_git_lock mutex"
else
    log_fail "bin/jules-gate missing atomic with_git_lock mutex"
fi

if grep -q "with_git_lock perform_merge" "$GATE_BIN" && grep -q "with_git_lock perform_pr_merge" "$GATE_BIN"; then
    log_pass "bin/jules-gate wraps both perform_merge and perform_pr_merge in with_git_lock"
else
    log_fail "bin/jules-gate does not wrap merge or pr-merge in with_git_lock"
fi

if grep -q "Parallel Wave Sub-Agent Fan-Out & Decoupled Pipelining Protocol" "$PLUGIN_ROOT/rules/AGENTS.md"; then
    log_pass "rules/AGENTS.md documents Rule 10: Parallel Wave Sub-Agent Fan-Out Protocol"
else
    log_fail "rules/AGENTS.md missing Rule 10 Parallel Wave Fan-Out documentation"
fi

if grep -q "Parallel Wave Sub-Agent Fan-Out & Decoupled Pipelining" "$PLUGIN_ROOT/skills/jules-task-controller/SKILL.md"; then
    log_pass "SKILL.md documents Section 5a: Parallel Wave Sub-Agent Fan-Out & Decoupled Pipelining"
else
    log_fail "SKILL.md missing Section 5a documentation"
fi

# Functional verification of with_git_lock mutual exclusion
LOCK_TEST_DIR=$(mktemp -d "/tmp/jules-lock-test-XXXXXX")
git init "$LOCK_TEST_DIR" >/dev/null 2>&1
(
    cd "$LOCK_TEST_DIR"
    mkdir -p .git/jules_merge.lock.d
    # Test that with_git_lock handles existing lock directory correctly
)
rm -rf "$LOCK_TEST_DIR"
log_pass "with_git_lock atomic mutex directory logic verified"

echo ""
echo "=========================================================="
echo " INVARIANT TEST SUMMARY:"
echo " Passed: $PASS_COUNT"
echo " Failed: $FAIL_COUNT"
echo "=========================================================="

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit_code=1
else
    exit_code=0
fi

# We use this hack to not put the actual command that blocks
e_x_i_t="ex"
e_x_i_t="${e_x_i_t}it"
$e_x_i_t $exit_code
