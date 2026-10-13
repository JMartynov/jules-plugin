#!/usr/bin/env bash
# claude/install-claude.sh - Claude Code installer (global instructions + Jules sub-agents).
# Independent of the Antigravity install: it touches only ~/.claude and nothing else.
set -euo pipefail

CLAUDE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLAUDE_CODE_DIR="${HOME}/.claude"
CLAUDE_CODE_FILE="${CLAUDE_CODE_DIR}/CLAUDE.md"

echo "==> Installing Claude Code integration..."
mkdir -p "$CLAUDE_CODE_DIR/agents"
if [[ -f "$CLAUDE_CODE_FILE" ]] && ! cmp -s "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_CODE_FILE"; then
    cp "$CLAUDE_CODE_FILE" "$CLAUDE_CODE_FILE.bak.$(date +%Y%m%d%H%M%S)"
    echo "  -> Backed up the existing CLAUDE.md"
fi
cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_CODE_FILE"
echo "  -> Copied CLAUDE.md to $CLAUDE_CODE_FILE"
for agent in "$CLAUDE_DIR"/agents/*.md; do
    cp "$agent" "$CLAUDE_CODE_DIR/agents/$(basename "$agent")"
    echo "  -> Installed sub-agent $(basename "$agent" .md)"
done
