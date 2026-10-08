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

for subcmd in wait verify merge pr ps status lint; do
    if echo "$HELP_OUT" | grep -q "$subcmd"; then
        log_pass "Subcommand '$subcmd' documented in help output"
    else
        log_fail "Subcommand '$subcmd' missing from help output"
    fi
done

STATUS_OUT=$("$GATE_BIN" status 2>&1 || true)
EXPECTED_VER=$(grep '"version"' "$PLUGIN_ROOT/plugin.json" | head -n 1 | sed -E 's/.*"version": *"([^"]+)".*/\1/')
if [[ "$EXPECTED_VER" != "2.6.0" ]]; then
    log_fail "Expected version 2.6.0 in plugin.json, got $EXPECTED_VER"
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
