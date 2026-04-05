#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LINK_NAME="skill-update-team"

# 1. Create skills directory
mkdir -p "$SKILL_DIR"

# 2. Symlink repo into skills directory
if [ -L "$SKILL_DIR/$LINK_NAME" ]; then
  echo "Removing existing symlink..."
  rm "$SKILL_DIR/$LINK_NAME"
fi

ln -s "$REPO_DIR" "$SKILL_DIR/$LINK_NAME"

# 3. Success
echo ""
echo "Skill Update Team installed successfully!"
echo "  Linked: $SKILL_DIR/$LINK_NAME -> $REPO_DIR"
echo ""
echo "Please restart Claude Code to activate the skill."
echo "Then type: /skill-update-team"
