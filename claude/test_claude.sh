#!/usr/bin/env bash
# Checks for the Claude Code part only. Does not touch the Antigravity files or the real HOME.
set -uo pipefail
D="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PASS=0; FAIL=0
ok(){ echo "  ✅ [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ [FAIL] $1"; FAIL=$((FAIL+1)); }
for a in jules-dispatcher jules-verifier jules-researcher; do
  f="$D/agents/$a.md"
  if [[ -f "$f" ]] && head -1 "$f" | grep -q '^---$' && grep -q "^name: $a$" "$f" && grep -q '^model: ' "$f" && grep -q '^tools: ' "$f" && grep -q "$a" "$D/CLAUDE.md"; then ok "$a: frontmatter valid, referenced in CLAUDE.md"; else bad "$a: missing, malformed or not referenced"; fi
done
if ! grep -q '^tools:.*\(Edit\|Write\)' "$D"/agents/*.md; then ok "sub-agents have no Edit or Write tool"; else bad "a sub-agent has Edit or Write"; fi
grep -q "Writing Jules prompts" "$D/CLAUDE.md" && grep -q "fallback" "$D/CLAUDE.md" && ok "CLAUDE.md has the prompt-writing lessons" || bad "CLAUDE.md lacks the prompt-writing lessons"
S="$D/../skills/jules-task-controller/SKILL.md"
grep -q "Prompting Rules" "$S" && grep -q "Defaults when blocked" "$S" && ok "SKILL.md has the prompting rules and the blocked-defaults section" || bad "SKILL.md lacks the new sections"
# jules-watch.sh: maps the exit code of `jules-gate wait` to one final result line (fake jules-gate on PATH)
W="$D/jules-watch.sh"; FB=$(mktemp -d /tmp/jules-watch-test-XXXXXX)
cat > "$FB/jules-gate" <<'EOS'
#!/usr/bin/env bash
if [[ "$1" == "wait" ]]; then echo "waiting $2 $3 $4 $5 $6"; exit "${FAKE_RC:-0}"; fi
if [[ "$1" == "inspect" ]]; then echo "Jules Question / Prompt: Is this ok?"; exit 10; fi
EOS
chmod +x "$FB/jules-gate"
for pair in "0:COMPLETED" "10:NEEDS_INPUT" "1:TIMEOUT" "2:FAILED" "7:FAILED"; do
  rc="${pair%%:*}"; want="${pair##*:}"
  out=$(PATH="$FB:$PATH" FAKE_RC=$rc bash "$W" 12345 2>&1); got=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  [[ "$last" == "JULES_RESULT status=$want session=12345" && "$got" == "$rc" ]] && ok "jules-watch: exit $rc -> $want (same exit code)" || bad "jules-watch exit $rc gave '$last' rc=$got"
done
out=$(PATH="$FB:$PATH" FAKE_RC=10 bash "$W" 12345 2>&1)
[[ "$out" == *"Is this ok?"* ]] && ok "jules-watch prints the question on NEEDS_INPUT" || bad "question not printed"
out=$(PATH="$FB:$PATH" FAKE_RC=0 bash "$W" 12345 90 2>&1)
[[ "$out" == *"--interactive --timeout 90"* ]] && ok "jules-watch passes --interactive and the timeout" || bad "args not passed: $out"
out=$(PATH="$FB:$PATH" bash "$W" "abc; rm -rf /" 2>&1); [[ $? == 64 ]] && ok "jules-watch rejects a non-numeric session id (exit 64)" || bad "session id not validated"
rm -rf "$FB"
D2="$D/agents/jules-dispatcher.md"
grep -q "never waits" "$D/CLAUDE.md" && grep -q "run_in_background" "$D/CLAUDE.md" && grep -q "re-arm" "$D/CLAUDE.md" && ok "CLAUDE.md flow: background watcher, re-arm rule" || bad "CLAUDE.md flow not updated"
grep -q "DISPATCHED" "$D2" && ! grep -q "jules-gate wait <session" "$D2" && ok "dispatcher agent dispatches only (no wait step)" || bad "dispatcher still waits"
H=$(mktemp -d /tmp/jules-claude-test-XXXXXX)
HOME="$H" "$D/install-claude.sh" >/dev/null 2>&1
if [[ -f "$H/.claude/CLAUDE.md" && -f "$H/.claude/agents/jules-dispatcher.md" && -f "$H/.claude/agents/jules-verifier.md" && -f "$H/.claude/agents/jules-researcher.md" && -x "$H/.claude/jules-watch.sh" && ! -e "$H/.local" && ! -e "$H/.gemini" ]]; then ok "install-claude.sh installs only under ~/.claude"; else bad "install-claude.sh result wrong"; fi
rm -rf "$H"
echo " Passed: $PASS  Failed: $FAIL"; [[ $FAIL -eq 0 ]]
