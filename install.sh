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
  ln -sfn "${skill_dir}" "${CLAUDE_DIR}/skills/${skill_name}"
  echo "  skill:   ${skill_name}"
done

echo ""
echo "Done. Verify with: /task (in Claude Code)"
