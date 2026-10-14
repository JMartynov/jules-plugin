#!/usr/bin/env bash
# worktree_gate.sh - Generic, Language-Agnostic Gated Verification for Jules
# Pulls Jules patch, applies to an isolated branch, runs project tests, and gates integration.

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

usage() {
    echo "Usage: $0 <session_id> [base_branch] [--sandbox] [--retry-flaky <N>]"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

SESSION_ID=""
BASE_BRANCH=""
SANDBOX=false
RETRY_FLAKY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sandbox)
            SANDBOX=true
            shift
            ;;
        --retry-flaky)
            RETRY_FLAKY="$2"
            shift 2
            ;;
        *)
            if [[ -z "$SESSION_ID" ]]; then
                SESSION_ID="$1"
            elif [[ -z "$BASE_BRANCH" ]]; then
                BASE_BRANCH="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$SESSION_ID" ]]; then
    usage
fi

BASE_BRANCH="${BASE_BRANCH:-$(git branch --show-current 2>/dev/null || echo 'main')}"
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    if [[ "$BASE_BRANCH" == "main" ]] && git rev-parse --verify "master" >/dev/null 2>&1; then
        BASE_BRANCH="master"
    elif [[ "$BASE_BRANCH" == "master" ]] && git rev-parse --verify "main" >/dev/null 2>&1; then
        BASE_BRANCH="main"
    fi
fi
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
if ! jules remote pull --session "$SESSION_ID" > "$PATCH_FILE" 2>&1; then
    echo "❌ Failed to pull patch for session $SESSION_ID"
    rm -rf "$PATCH_FILE"
    exit 1
fi

if [[ ! -s "$PATCH_FILE" ]]; then
    echo "❌ Patch file is empty. Nothing to verify."
    rm -rf "$PATCH_FILE"
    exit 1
fi

echo "Patch summary:"
git apply --stat "$PATCH_FILE" 2>/dev/null || head -n 20 "$PATCH_FILE"

# Save the original directory right at the start to ensure safe cleanup traps
ORIGINAL_DIR="$PWD"

# 2. Set up true isolated git worktree
WORKTREE_DIR=$(mktemp -d "/tmp/jules-worktree-${SESSION_ID}-XXXXXX")
echo "==> Creating isolated worktree at $WORKTREE_DIR..."

cleanup() {
    echo "==> Cleaning up isolated worktree..."
    cd "$ORIGINAL_DIR" 2>/dev/null || true
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    git branch -D "$REVIEW_BRANCH" 2>/dev/null || true
    rm -rf "$WORKTREE_DIR"
    rm -rf "$PATCH_FILE"
}

# Trap signals for safe cleanup on interruption
trap 'cleanup' EXIT INT TERM

# Ensure branch does not already exist locally
git branch -D "$REVIEW_BRANCH" 2>/dev/null || true

# Add the worktree
git worktree add -b "$REVIEW_BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH"

# Change directory to the isolated worktree
cd "$WORKTREE_DIR"

# 3. Protected Path Gating
echo "==> Inspecting patch for protected path modifications..."
PATCH_PATHS=$(git apply --numstat "$ORIGINAL_DIR/$PATCH_FILE" | awk '{print $3}')
# Secret files are always blocked.
if echo "$PATCH_PATHS" | grep -E '^\.env(\..*)?$' >/dev/null; then
    echo "❌ SECURITY VIOLATION: Patch attempts to modify protected infrastructure or secret files."
    exit 6
fi
# CI/CD definitions are blocked unless the operator opts in explicitly (JULES_GATE_ALLOW_CI=1).
CI_PATHS=$(echo "$PATCH_PATHS" | grep -E '^\.github/workflows/|^\.circleci/' || true)
if [[ -n "$CI_PATHS" ]]; then
    if [[ "${JULES_GATE_ALLOW_CI:-}" == "1" ]]; then
        echo "⚠️  JULES_GATE_ALLOW_CI=1: allowing CI/CD file changes (review them before pushing):"
        echo "$CI_PATHS" | sed 's/^/     /'
    else
        echo "❌ SECURITY VIOLATION: Patch attempts to modify protected infrastructure or secret files."
        echo "   (set JULES_GATE_ALLOW_CI=1 to allow CI/CD file changes after you have reviewed them)"
        exit 6
    fi
fi

# 4. Apply patch
echo "==> Applying patch..."
if ! git apply "$ORIGINAL_DIR/$PATCH_FILE" 2>/dev/null; then
    echo "❌ Patch did not apply cleanly to $REVIEW_BRANCH"
    exit 2
fi

# Stage applied changes
git add -A

# 4. Auto-detect and execute test runner
echo "==> Detecting test runner..."
TEST_CMD=""

if [[ -f "pyproject.toml" || -f "pytest.ini" || -f "setup.py" || -f "requirements.txt" || -n "$(find . -maxdepth 2 -name 'test_*.py' 2>/dev/null | head -n 1)" || (-d "tests" && -n "$(find tests -name '*.py' 2>/dev/null | head -n 1)") ]]; then
    if python3 -m pytest --version >/dev/null 2>&1; then
        TEST_CMD="python3 -m pytest"
    elif command -v pytest >/dev/null 2>&1 && pytest --version >/dev/null 2>&1; then
        TEST_CMD="pytest"
    else
        TEST_CMD="python3 -m unittest discover -s . -p 'test_*.py'"
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

# Optional override (off by default): a project whose tests need its own runner, e.g. JULES_GATE_TEST_CMD="uv run pytest -q"
if [[ -n "${JULES_GATE_TEST_CMD:-}" ]]; then
    TEST_CMD="$JULES_GATE_TEST_CMD"
    echo "==> Test runner overridden by JULES_GATE_TEST_CMD"
fi

if [[ -n "$TEST_CMD" ]]; then
    if [[ "$SANDBOX" == "true" ]]; then
        CONTAINER_ENGINE=""
        if command -v podman >/dev/null 2>&1; then
            CONTAINER_ENGINE="podman"
        elif command -v docker >/dev/null 2>&1; then
            CONTAINER_ENGINE="docker"
        fi

        if [[ -n "$CONTAINER_ENGINE" ]]; then
            IMAGE=""
            if [[ "$TEST_CMD" == *"pytest"* || "$TEST_CMD" == *"python"* ]]; then
                IMAGE="python:3.11-slim"
            elif [[ "$TEST_CMD" == *"npm"* ]]; then
                IMAGE="node:lts-slim"
            elif [[ "$TEST_CMD" == *"cargo"* ]]; then
                IMAGE="rust:slim"
            elif [[ "$TEST_CMD" == *"go "* ]]; then
                IMAGE="golang:alpine"
            else
                IMAGE="ubuntu:latest"
            fi
            
            echo "==> [--sandbox] Wrapping test command in $CONTAINER_ENGINE ($IMAGE)..."
            TEST_CMD="$CONTAINER_ENGINE run --rm --network none -v $(pwd):/workspace -w /workspace $IMAGE $TEST_CMD"
        else
            echo "[--sandbox] Container runtime (docker/podman) not found. Falling back to host execution."
        fi
    fi

    echo "==> Running local verification: $TEST_CMD"
    TEST_LOG=$(mktemp "/tmp/jules-test-XXXXXX")
    
    PASSED=false
    
    # First attempt
    if $TEST_CMD > "$TEST_LOG" 2>&1; then
        echo "✅ All tests passed on branch $REVIEW_BRANCH!"
        rm -f "$TEST_LOG"
        PASSED=true
    else
        # Retry loop
        for (( i=1; i<=RETRY_FLAKY; i++ )); do
            echo "==> Retrying flaky test (Attempt $i/$RETRY_FLAKY)..."
            if $TEST_CMD > "$TEST_LOG" 2>&1; then
                echo "⚠️  [FLAKY TEST RESOLVED] Test suite passed on retry attempt $i/$RETRY_FLAKY!"
                rm -f "$TEST_LOG"
                PASSED=true
                break
            fi
        done
    fi

    if [[ "$PASSED" == "false" ]]; then
        echo "❌ Tests failed on branch $REVIEW_BRANCH. Reverting changes."
        echo "--- [Test Failure Diagnostics] ---"
        grep -E "^(FAILED|ERROR|=== FAIL|FAIL:) " "$TEST_LOG" | head -n 15 || true
        
        # Secret Redaction Filter: Update the actual file so reply gets safe contents
        # -z flag allows matching across multiple lines (useful for private keys)
        sed -i -z -E -e 's/AKIA[0-9A-Z]{16}/[REDACTED AWS KEY]/g' \
                 -e 's/gh[pousr]_[0-9A-Za-z]{36}/[REDACTED GITHUB TOKEN]/g' \
                 -e 's/Bearer [a-zA-Z0-9\-\._~+=\/]+/[REDACTED BEARER TOKEN]/g' \
                 -e 's/-----BEGIN [A-Z ]+ PRIVATE KEY-----[^-]+-----END [A-Z ]+ PRIVATE KEY-----/[REDACTED PRIVATE KEY]/g' \
                 "$TEST_LOG"
                 
        echo "--- [Test Failure Summary (Last 40 lines, redacted)] ---"
        tail -n 40 "$TEST_LOG"
        
        echo "💡 Tip: Run \"jules-gate reply $SESSION_ID $TEST_LOG\" to copy the failure trace and open the Cloud VM for zero-overhead in-VM repair."
        # Not removing $TEST_LOG here because we suggest using it in the reply command
        exit 3
    fi
else
    echo "⚠️  No automated test suite detected. Changes applied and staged."
fi

# 5. Commit review branch & record telemetry
NUMSTAT=$(git diff --numstat HEAD~1 2>/dev/null || echo "0 0")
LINES_ADDED=$(echo "$NUMSTAT" | awk '{sum+=$1} END {print sum+0}')
LINES_REMOVED=$(echo "$NUMSTAT" | awk '{sum+=$2} END {print sum+0}')
DIFF_LINES=$(( LINES_ADDED + LINES_REMOVED ))
ESTIMATED_TOKENS=$(( 35000 + DIFF_LINES * 5 ))

TELEMETRY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/jules-gate"
mkdir -p "$TELEMETRY_DIR" 2>/dev/null || true
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d")
REPO_NAME=$(git config --get remote.origin.url 2>/dev/null || basename "$(pwd)")
echo "$TIMESTAMP|$SESSION_ID|$REPO_NAME|verified|$LINES_ADDED|$LINES_REMOVED|$ESTIMATED_TOKENS" >> "$TELEMETRY_DIR/telemetry.log" 2>/dev/null || true

git commit -m "jules($SESSION_ID): verified changes applied from remote session" || true

# Change back to original directory before cleanup
cd "$ORIGINAL_DIR"

# Remove trap and clean up worktree but keep the branch
trap - EXIT INT TERM
git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
rm -rf "$WORKTREE_DIR"
rm -rf "$PATCH_FILE"

echo "=========================================================="
echo "🎉 Verification successful! Review branch '$REVIEW_BRANCH' is ready."
echo "  🌐 Jules Web Task: https://jules.google.com/task/$SESSION_ID"
echo "To merge into $BASE_BRANCH:"
echo "  git checkout $BASE_BRANCH && git merge --no-ff $REVIEW_BRANCH"
echo "To create a GitHub PR:"
echo "  git push origin $REVIEW_BRANCH && gh pr create --fill"
echo "=========================================================="

exit 0
