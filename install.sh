#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"

echo "Installing claude-pm from ${REPO_DIR}"

# Ensure target directories exist
mkdir -p "${CLAUDE_DIR}/commands"
mkdir -p "${CLAUDE_DIR}/skills"

# Symlink command
ln -sfn "${REPO_DIR}/commands/task.md" "${CLAUDE_DIR}/commands/task.md"
echo "  command: task.md"

# Symlink skills
for skill_dir in "${REPO_DIR}"/skills/*/; do
  skill_name="$(basename "$skill_dir")"
  target="${CLAUDE_DIR}/skills/${skill_name}"
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    echo "ERROR: ${target} exists as a real directory (not a symlink)."
    echo "       Remove it manually and re-run: rm -rf ${target}"
    exit 1
  fi
  ln -sfn "${skill_dir}" "$target"
  echo "  skill:   ${skill_name}"
done

echo ""
echo "Done. Verify with: /task (in Claude Code)"
