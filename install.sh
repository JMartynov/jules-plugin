#!/usr/bin/env bash
# install.sh - Global installer for Jules Task Controller Plugin
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN_DIR="${HOME}/.local/bin"
PLUGIN_DIR="${HOME}/.gemini/config/plugins/jules-plugin"
SKILL_DIR="${HOME}/.gemini/config/skills/jules-task-controller"

echo "=========================================================="
echo " Installing Jules Task Controller (Version 2.0)"
echo " Source: $REPO_DIR"
echo "=========================================================="

# 1. Create target directories
mkdir -p "$BIN_DIR"
mkdir -p "$(dirname "$PLUGIN_DIR")"
mkdir -p "$(dirname "$SKILL_DIR")"

# 2. Link binary to ~/.local/bin
echo "==> Linking jules-gate to $BIN_DIR/jules-gate..."
ln -sfn "$REPO_DIR/bin/jules-gate" "$BIN_DIR/jules-gate"
chmod +x "$REPO_DIR/bin/jules-gate"
chmod +x "$REPO_DIR/scripts/"*.sh

# 3. If cloned outside default plugins directory, link to global plugin directory
if [[ "$REPO_DIR" != "$PLUGIN_DIR" ]]; then
    echo "==> Linking plugin to Antigravity global plugin directory: $PLUGIN_DIR..."
    ln -sfn "$REPO_DIR" "$PLUGIN_DIR"
fi

# 4. Link skill for direct global discovery
echo "==> Linking skill to $SKILL_DIR..."
ln -sfn "$REPO_DIR/skills/jules-task-controller" "$SKILL_DIR"

echo "=========================================================="
echo "🎉 Installation complete!"
echo "Verify with:"
echo "  jules-gate help"
echo "=========================================================="
