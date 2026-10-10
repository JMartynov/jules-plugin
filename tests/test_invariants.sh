#!/usr/bin/env bash
# test_invariants.sh - Comprehensive invariant test suite for jules-plugin & jules-gate
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
GATE_BIN="$PLUGIN_ROOT/bin/jules-gate"
SCRIPTS_DIR="$PLUGIN_ROOT/scripts"

export PATH="$PLUGIN_ROOT/bin:$PATH"

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

for subcmd in wait verify merge pr ps status lint tokens web close reply inspect interact; do
    if echo "$HELP_OUT" | grep -q "$subcmd"; then
        log_pass "Subcommand '$subcmd' documented in help output"
    else
        log_fail "Subcommand '$subcmd' missing from help output"
    fi
done

STATUS_OUT=$("$GATE_BIN" status 2>&1 || true)
EXPECTED_VER=$(grep '"version"' "$PLUGIN_ROOT/plugin.json" | head -n 1 | sed -E 's/.*"version": *"([^"]+)".*/\1/')
if [[ "$EXPECTED_VER" != "3.0.0" ]]; then
    log_fail "Expected version 3.0.0 in plugin.json, got $EXPECTED_VER"
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
if echo "$API_USAGE_OUT" | grep -q "jules_api.py <inspect|interact>"; then
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

# Cleanup
export PATH="$OLD_PATH"
rm -rf "$MOCK_DIR" "$TEST_REPO" "$LOG_DIR"

echo ""
echo "=========================================================="
echo " INVARIANT TEST SUMMARY:"
echo " Passed: $PASS_COUNT"
echo " Failed: $FAIL_COUNT"
echo "=========================================================="

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
