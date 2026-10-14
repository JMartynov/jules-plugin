#!/usr/bin/env bash
# jules-gate lint: prompt-quality hints (warnings only, never a failure) with a fake `jules` CLI.
set -uo pipefail
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
GATE="$ROOT/bin/jules-gate"
PASS=0; FAIL=0
ok(){ echo "  ✅ [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ [FAIL] $1"; FAIL=$((FAIL+1)); }
T=$(mktemp -d /tmp/jules-lint-XXXXXX); mkdir -p "$T/bin"
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
echo "owner/repo"
EOS
chmod +x "$T/bin/jules"
lint(){ PATH="$T/bin:$PATH" bash "$GATE" lint owner/repo "$1" 2>&1; }

GOOD="$T/good.md"
cat > "$GOOD" <<'EOS'
# Task: add a test for parse_header in src/app/parser.py
Run `uv run pytest tests/test_parser.py -q` while working and the full suite once at the end.
If a rule cannot be met, leave the code as it was, say so in the summary and do not ask.
Finalize directly without asking open-ended questions.
EOS
out=$(lint "$GOOD")
has(){ [[ "$1" == *"$2"* ]]; }   # no pipes: grep -q on a pipe fails under pipefail (SIGPIPE)
has "$out" "Prompt File" || bad "lint did not reach the prompt checks"
has "$out" "Pre-flight checks passed" && ok "lint runs to the end for a prompt without prohibitions (set -e safe)" || bad "lint aborted early"
if has "$out" "Conflict Tip" || has "$out" "Scope Tip" || has "$out" "Output Tip" || has "$out" "Specificity Tip"; then bad "good prompt got a tip"; else ok "a good prompt gets no quality tips"; fi

CONFLICT="$T/conflict.md"
cat > "$CONFLICT" <<'EOS'
# Task: fix typing in src/app/x.py
Do not change behaviour. Never add type: ignore. Do not add overrides. Must not skip tests. Do not touch other files.
Run uv run mypy -q src.
EOS
out=$(lint "$CONFLICT"); has "$out" "Conflict Tip" && ok "many prohibitions without a fallback -> Conflict Tip" || bad "no conflict tip"
has "$out" "exists" && ok "hints do not fail the lint" || bad "lint failed"

LONG="$T/long.md"
{ echo "# Task: big work in src/a.py"; for i in $(seq 1 12); do echo "$i. step number $i in src/a.py"; done; for i in $(seq 1 80); do echo "line $i"; done; } > "$LONG"
out=$(lint "$LONG"); has "$out" "Scope Tip" && ok "long prompt with many steps -> Scope Tip" || bad "no scope tip"

NOLIMIT="$T/nolimit.md"
printf '# Task: update src/a.py\nRun the whole test suite with pytest and report. Otherwise leave it. Do not ask.\n' > "$NOLIMIT"
out=$(lint "$NOLIMIT"); has "$out" "Output Tip" && ok "test runner without an output limit -> Output Tip" || bad "no output tip"

VAGUE="$T/vague.md"
printf 'Make the code better and faster, do not ask.\n' > "$VAGUE"
out=$(lint "$VAGUE"); has "$out" "Specificity Tip" && ok "no file names -> Specificity Tip" || bad "no specificity tip"
rm -rf "$T"; echo " Passed: $PASS  Failed: $FAIL"; [[ $FAIL -eq 0 ]]
