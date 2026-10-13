# Claude Code part of the Jules pipeline

Everything specific to Claude Code lives in this folder. Antigravity does not read it, and nothing here changes the Antigravity files (`skills/`, `rules/`, `bin/`, `scripts/`). The CLI (`jules-gate`) and the scripts are shared.

- `CLAUDE.md`: global instructions installed to `~/.claude/CLAUDE.md` (an existing different file is backed up as `CLAUDE.md.bak.<time>`).
- `agents/`: sub-agents installed to `~/.claude/agents/`: `jules-researcher` (haiku, read-only), `jules-dispatcher` (haiku: lint, `jules remote new`, `jules-gate wait --interactive`), `jules-verifier` (sonnet: `jules-gate verify`, diff check, merge into the named branch). They match Antigravity's research, `flash_lite` and `flash` tiers.
- `install-claude.sh`: the installer. `./install.sh --claude-code` (or `--all`) calls it; it can also be run alone. It writes only under `~/.claude`.
- `test_claude.sh`: checks for this folder only.

A Claude Code sub-agent cannot message the main thread while running, so the dispatcher returns `NEEDS_INPUT` or `STILL_RUNNING` and the main thread answers or restarts it. New agents are picked up in a new Claude Code session.
