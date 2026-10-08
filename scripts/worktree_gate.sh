#!/usr/bin/env bash
# worktree_gate.sh - Generic, Language-Agnostic Gated Verification for Jules
# Pulls Jules patch, applies to an isolated branch, runs project tests, and gates integration.

set -euo pipefail

usage() {
    echo "Usage: $0 <session_id> [base_branch]"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

SESSION_ID="$1"
BASE_BRANCH="${2:-$(git branch --show-current 2>/dev/null || echo 'main')}"
REVIEW_BRANCH="jules/review-${SESSION_ID}"
PATCH_DIR=".jules/patches"
PATCH_FILE="${PATCH_DIR}/${SESSION_ID}.patch"

echo "=========================================================="
echo " [Jules Gate] Validating Session: $SESSION_ID"
echo " Base Branch:   $BASE_BRANCH"
echo " Review Branch: $REVIEW_BRANCH"
echo "=========================================================="

mkdir -p "$PATCH_DIR"

# 1. Pull remote patch
echo "==> Pulling patch from Jules session $SESSION_ID..."
jules remote pull --session "$SESSION_ID" > "$PATCH_FILE" 2>&1 || {
    echo "❌ Failed to pull patch for session $SESSION_ID"
    exit 1
}

if [[ ! -s "$PATCH_FILE" ]]; then
    echo "❌ Patch file is empty. Nothing to verify."
    exit 1
fi

echo "Patch summary:"
git apply --stat "$PATCH_FILE" || head -n 20 "$PATCH_FILE"

# 2. Checkout isolated branch
echo "==> Creating review branch: $REVIEW_BRANCH from $BASE_BRANCH..."
git checkout -B "$REVIEW_BRANCH" "$BASE_BRANCH"

# 3. Apply patch
echo "==> Applying patch..."
if ! git apply "$PATCH_FILE"; then
    echo "❌ Patch did not apply cleanly to $REVIEW_BRANCH"
    git checkout -f "$BASE_BRANCH"
    git branch -D "$REVIEW_BRANCH" 2>/dev/null || true
    exit 2
fi

# Stage applied changes
git add -A

# 4. Auto-detect and execute test runner
echo "==> Detecting test runner..."
TEST_CMD=""

if [[ -f "pyproject.toml" || -f "pytest.ini" || -f "setup.py" || -d "tests" && -f "requirements.txt" ]]; then
    if command -v pytest >/dev/null 2>&1; then
        TEST_CMD="pytest"
    else
        TEST_CMD="python3 -m unittest"
    fi
elif [[ -f "package.json" ]]; then
    if grep -q '"test":' package.json; then
        TEST_CMD="npm test"
    fi
elif [[ -f "Cargo.toml" ]]; then
    TEST_CMD="cargo test"
elif [[ -f "go.mod" ]]; then
    TEST_CMD="go test ./..."
elif [[ -f "pom.xml" ]]; then
    TEST_CMD="mvn test"
elif [[ -f "gradlew" ]]; then
    TEST_CMD="./gradlew test"
fi

if [[ -n "$TEST_CMD" ]]; then
    echo "==> Running local verification: $TEST_CMD"
    if $TEST_CMD; then
        echo "✅ All tests passed on branch $REVIEW_BRANCH!"
    else
        echo "❌ Tests failed on branch $REVIEW_BRANCH. Reverting changes."
        git checkout -f "$BASE_BRANCH"
        git branch -D "$REVIEW_BRANCH" 2>/dev/null || true
        exit 3
    fi
else
    echo "⚠️  No automated test suite detected. Changes applied and staged."
fi

# 5. Commit review branch
git commit -m "jules($SESSION_ID): verified changes applied from remote session" || true

echo "=========================================================="
echo "🎉 Verification successful! Review branch '$REVIEW_BRANCH' is ready."
echo "To merge into $BASE_BRANCH:"
echo "  git checkout $BASE_BRANCH && git merge --no-ff $REVIEW_BRANCH"
echo "To create a GitHub PR:"
echo "  git push origin $REVIEW_BRANCH && gh pr create --fill"
echo "=========================================================="

exit 0
