# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

claude-pm is a task pipeline for Claude Code that uses **GitHub Projects as a shared state machine**. Tasks flow through 8 stages: Idea → Define → Design → Plan → Implement → Verify → Ship → Done. The entry point is the `/task` command.

## Architecture

**Command orchestrates, scripts execute, skills converse.** Three-layer separation:

- `commands/task.md` — The `/task` command. Handles argument parsing, config loading, skill invocation, and phase transition decisions. This is the router and state manager.
- `bin/` — Shell scripts that encapsulate all GitHub CLI operations. The command prompt calls them via Bash; they auto-load config from `~/.config/claude-pm/`. Installed to `~/.claude/bin/claude-pm/` via symlink. Scripts are deterministic — given the same inputs, they produce the same API calls.
- `skills/task-{define,design,plan,implement,verify,ship}/SKILL.md` — Six phase skills (plus `gh-cli/SKILL.md`, a reference guide for GitHub CLI patterns). Each phase skill receives a labeled context block from the command, does its work conversationally, and outputs a `completion` fenced block that the command parses to determine next steps.

Skills are stateless — they don't read or write the board directly. The command feeds them context and processes their output. Skills can also work standalone outside the pipeline.

## Key conventions

- **Config**: Per-repo at `~/.config/claude-pm/<repo>.taskboard.json` — contains project IDs, field IDs, status option IDs
- **Plan files**: `plans/<issue_number>-short-title.md` — living documents that grow through the pipeline (problem statement → design → implementation plan → checked-off criteria). Named by GitHub Issue number, not zero-padded.
- **Session log**: Timestamped entries in the GitHub Issue body, format `[YYYY-MM-DD HH:MM] **Event** details`
- **Body editing**: Use `task-issue-view` and `task-issue-edit-body` scripts (read-append-write pattern via stdin).
- **Completion protocol**: Skills signal phase completion via a fenced `completion` block with fields: `status`, `plan`, `summary`, and optionally `regress_to`, `rework`, `impl`, `comment`
- **Implementation IDs**: `impl-1`, `impl-2`, etc. — rework creates a new ID, fresh Verify each time
- **Comments as artifacts**: The issue body holds a scannable session timeline (one-liners). Phase artifacts (problem statements, design rationale, verification reports, ship summaries) are posted as issue comments via the `comment` field in skill completion blocks.

## Installation

```bash
./install.sh
```

Symlinks `commands/task.md`, all `skills/*/` directories, and `bin/` (as `bin/claude-pm/`) into `~/.claude/`.

## VCS

This repo uses Jujutsu (`jj`). A `.jj/` directory exists — do not use raw git commands that modify state.

## Dependencies

- GitHub CLI (`gh`) authenticated with the `project` scope (implies `read:project`)
- `gh auth refresh -h github.com -s project` — the `-h github.com` flag is required in non-interactive terminals or the command hangs
- GraphQL API needed to edit single-select field options (CLI can't do this directly)

## GitHub Projects API limitations

- **No view mutations**: The GraphQL API has no `createProjectV2View` or `updateProjectV2View` mutations. Views (table, board, roadmap) cannot be created or modified programmatically — only through the UI.
- **Default view is always Table**: `gh project create` and `gh project view --web` both use the default table layout. To open a board, construct the URL directly with `?layout=board` appended (e.g. `https://github.com/orgs/<owner>/projects/<number>?layout=board`).
- **URL format varies by owner type**: orgs use `/orgs/<owner>/projects/<n>`, users use `/users/<owner>/projects/<n>`. The `owner_type` field in config (`"User"` or `"Organization"`) determines which.

## Editing skills

Each skill SKILL.md has YAML frontmatter (`name`, `description`) and follows a strict structure: Input format → Conversation/work protocol → Phase confirmation → Completion block → Hard constraints. When editing skills, preserve this structure and the completion protocol — the command depends on parsing it.
