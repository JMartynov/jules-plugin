#!/usr/bin/env bash
# install.sh - Global installer for Jules Task Controller Plugin
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN_DIR="${HOME}/.local/bin"
PLUGIN_DIR="${HOME}/.gemini/config/plugins/jules-plugin"
SKILL_DIR="${HOME}/.gemini/config/skills/jules-task-controller"
CLAUDE_DESKTOP_CONFIG_DIR="${HOME}/Library/Application Support/Claude"
CLAUDE_DESKTOP_CONFIG_FILE="${CLAUDE_DESKTOP_CONFIG_DIR}/claude_desktop_config.json"
CLAUDE_CODE_DIR="${HOME}/.claude"
CLAUDE_CODE_FILE="${CLAUDE_CODE_DIR}/CLAUDE.md"

INSTALL_ANTIGRAVITY=true
INSTALL_CLAUDE_DESKTOP=false
INSTALL_CLAUDE_CODE=false

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --antigravity     Link Antigravity bin and skills (default behavior)."
    echo "  --claude-desktop  Safely add jules-gate MCP server to Claude Desktop config."
    echo "  --claude-code     Install ~/.claude/CLAUDE.md global instructions."
    echo "  --all             Install all targets simultaneously."
    echo "  -h, --help        Show this help message."
    echo ""
}

# Parse args
if [[ $# -gt 0 ]]; then
    INSTALL_ANTIGRAVITY=false
    for arg in "$@"; do
        case $arg in
            --antigravity)
                INSTALL_ANTIGRAVITY=true
                ;;
            --claude-desktop)
                INSTALL_CLAUDE_DESKTOP=true
                ;;
            --claude-code)
                INSTALL_CLAUDE_CODE=true
                ;;
            --all)
                INSTALL_ANTIGRAVITY=true
                INSTALL_CLAUDE_DESKTOP=true
                INSTALL_CLAUDE_CODE=true
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $arg"
                show_help
                exit 1
                ;;
        esac
    done
fi

if [[ $# -eq 0 ]]; then
    INSTALL_ANTIGRAVITY=true
fi

echo "=========================================================="
echo " Installing Jules Task Controller (Version 3.4.0)"
echo " Source: $REPO_DIR"
echo "=========================================================="

if [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
    echo "==> Installing Antigravity components..."
    mkdir -p "$BIN_DIR"
    mkdir -p "$(dirname "$PLUGIN_DIR")"
    mkdir -p "$(dirname "$SKILL_DIR")"

    echo "  -> Linking jules-gate to $BIN_DIR/jules-gate..."
    ln -sfn "$REPO_DIR/bin/jules-gate" "$BIN_DIR/jules-gate"
    chmod +x "$REPO_DIR/bin/jules-gate"
    chmod +x "$REPO_DIR/scripts/"*.py 2>/dev/null || true
    chmod +x "$REPO_DIR/scripts/"*.sh 2>/dev/null || true

    if [[ "$REPO_DIR" != "$PLUGIN_DIR" ]]; then
        echo "  -> Linking plugin to Antigravity global plugin directory: $PLUGIN_DIR..."
        ln -sfn "$REPO_DIR" "$PLUGIN_DIR"
    fi

    echo "  -> Linking skill to $SKILL_DIR..."
    ln -sfn "$REPO_DIR/skills/jules-task-controller" "$SKILL_DIR"
fi

if [[ "$INSTALL_CLAUDE_DESKTOP" == true ]]; then
    echo "==> Installing Claude Desktop MCP integration..."
    mkdir -p "$CLAUDE_DESKTOP_CONFIG_DIR"
    if [[ ! -f "$CLAUDE_DESKTOP_CONFIG_FILE" ]]; then
        echo "{}" > "$CLAUDE_DESKTOP_CONFIG_FILE"
    fi
    
    python3 -c "
import json
import sys
import os

config_file = '${CLAUDE_DESKTOP_CONFIG_FILE}'
repo_dir = '${REPO_DIR}'
mcp_script = os.path.join(repo_dir, 'scripts', 'jules_mcp.py')

try:
    with open(config_file, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}

if 'mcpServers' not in data:
    data['mcpServers'] = {}

data['mcpServers']['jules-gate'] = {
    'command': sys.executable,
    'args': [mcp_script]
}

with open(config_file, 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "  -> Updated $CLAUDE_DESKTOP_CONFIG_FILE"
fi

if [[ "$INSTALL_CLAUDE_CODE" == true ]]; then
    echo "==> Installing Claude Code integration..."
    "$REPO_DIR/claude/install-claude.sh"
fi

echo "=========================================================="
echo "🎉 Installation complete!"
if [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
    echo "Verify with:"
    echo "  jules-gate help"
fi
echo "=========================================================="
