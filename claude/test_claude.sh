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
H=$(mktemp -d /tmp/jules-claude-test-XXXXXX)
HOME="$H" "$D/install-claude.sh" >/dev/null 2>&1
if [[ -f "$H/.claude/CLAUDE.md" && -f "$H/.claude/agents/jules-dispatcher.md" && -f "$H/.claude/agents/jules-verifier.md" && -f "$H/.claude/agents/jules-researcher.md" && ! -e "$H/.local" && ! -e "$H/.gemini" ]]; then ok "install-claude.sh installs only under ~/.claude"; else bad "install-claude.sh result wrong"; fi
rm -rf "$H"
echo " Passed: $PASS  Failed: $FAIL"; [[ $FAIL -eq 0 ]]
