---
description: Task pipeline — manage development tasks through GitHub Projects
allowed-tools: Bash, Read, Glob, Grep, Write, Edit, AskUserQuestion, Skill
---

You are orchestrating a development task through a GitHub Projects pipeline. You handle all board I/O and delegate phase work to skills.

## Scripts

All GitHub CLI operations are handled by scripts in `~/.claude/bin/claude-pm/`. Each script auto-loads config from `~/.config/claude-pm/`. Scripts read long text (bodies, comments) from **stdin**.

| Script | Args | Stdin | Output |
|--------|------|-------|--------|
| `task-issue-create` | `<title>` | body text | JSON `{"number": N, "url": "..."}` |
| `task-issue-view` | `<number>` | — | raw body text |
| `task-issue-edit-body` | `<number>` | full body | confirmation |
| `task-issue-comment` | `<number>` | comment body | confirmation |
| `task-issue-close` | `<number>` | — | confirmation |
| `task-item-add` | `<issue_url>` | — | JSON (item ID) |
| `task-item-list` | — | — | JSON (full items array) |
| `task-item-find` | `<issue_number>` | — | JSON (single item) |
| `task-status-set` | `<item_id> <status_name>` | — | confirmation |
| `task-plan-set` | `<item_id> <plan_path>` | — | confirmation |
| `task-item-archive` | `<item_id>` | — | confirmation |
| `task-board-url` | — | — | URL text |
| `task-auth-check` | — | — | JSON `{gh_installed, authenticated, has_project_scope}` |
| `task-repo-info` | `<owner> <repo>` | — | JSON `{name, owner, owner_type, is_fork, parent_*}` |
| `task-project-list` | `<owner>` | — | JSON (project list) |
| `task-project-create` | `<owner> <title>` | — | JSON `{number, id}` |
| `task-project-delete` | `<pnum> <owner>` | — | confirmation |
| `task-field-create` | `<pnum> <owner> <name> <type>` | — | JSON `{id}` |
| `task-field-list` | `<pnum> <owner>` | — | JSON (field list) |
| `task-status-options-set` | `<field_id>` | — | JSON `{options: [{id, name}, ...]}` |

Call scripts with their full path: `~/.claude/bin/claude-pm/<script>`. Pass long text via stdin using heredoc or pipe, e.g.:

```bash
echo "$BODY" | ~/.claude/bin/claude-pm/task-issue-edit-body 7
```

## Argument parsing

Parse `$ARGUMENTS` to extract the subcommand and its arguments:

| Pattern | Subcommand | Args |
|---------|-----------|------|
| `new <rest>` | new | description = `<rest>` |
| `list` | list | (none) |
| `resume <number>` | resume | number |
| `resume` | resume | (prompt user) |
| `pause <rest>` | pause | note = `<rest>` (optional) |
| `note <rest>` | note | see note parsing below |
| `abandon <number> <rest>` | abandon | number, reason = `<rest>` (optional) |
| `setup` | setup | (none) |
| `board` | board | (none) |
| `teardown` | teardown | (none) |
| (empty or unrecognized) | help | (none) |

## Repo detection

Detect the current repo owner and name:

```bash
if [ -d ".jj" ]; then
  REMOTE_URL=$(jj git remote list 2>/dev/null | head -1 | awk '{print $2}')
elif [ -d "../.jj" ]; then
  REMOTE_URL=$(cd .. && jj git remote list 2>/dev/null | head -1 | awk '{print $2}')
else
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
fi

OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|.*github\.com[:/]||;s|\.git$||')
DETECTED_OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
DETECTED_REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)
```

Note: `DETECTED_OWNER` may be a personal fork rather than the actual org. The setup subcommand resolves forks and confirms with the user; other subcommands use the `owner` from the saved config. The config filename always uses `DETECTED_REPO` (which may be the fork name) so non-setup subcommands can find it via the local remote URL. The `repo` field inside the config stores the canonical (resolved) name, used for the GitHub Project title and display.

Load config from `~/.config/claude-pm/<DETECTED_REPO>.taskboard.json`. If missing, fail with: "No taskboard configured for this repo. Run `/task setup` first."

Store the loaded config in your working memory — you'll reference `project_number`, `owner`, `field_ids`, and `status_option_ids` throughout.

## Timestamp format

All timestamps use `YYYY-MM-DD HH:MM` in the user's local timezone. Generate with:
```bash
date '+%Y-%m-%d %H:%M'
```

---

## Subcommand: help

Display:

```
/task — Development task pipeline

  new <description>    Create task, start Define conversation
  list                 Board overview grouped by status
  resume [number]      Resume a task
  pause [note]         Save context, pause current task
  note [number] <text> Append note to task body
  abandon <number>     Archive task, delete plan file
  setup                Bootstrap GitHub Project for this repo
  board                Open the GitHub Project board in browser
  teardown             Delete GitHub Project and config for this repo
```

---

## Subcommand: setup

**Pre-flight checks** (fail gracefully with guidance at each step):

1. Check `gh` CLI installed and authenticated:
   ```bash
   ~/.claude/bin/claude-pm/task-auth-check
   ```
   If `gh_installed` is false → "Install the GitHub CLI: https://cli.github.com/"
   If `authenticated` is false → "Run `gh auth login` first."
   If `has_project_scope` is false:
   - Warn the user: "Missing project scope. This will print a URL and code — open the URL in your browser and enter the code to authorize."
   - Run: `gh auth refresh -h github.com -s project`
2. **Fork resolution**:
   ```bash
   ~/.claude/bin/claude-pm/task-repo-info "$DETECTED_OWNER" "$DETECTED_REPO"
   ```
   - If `is_fork` is true → set `RESOLVED_OWNER` to `parent_owner`, `RESOLVED_REPO` to `parent_name`
   - If not a fork → set `RESOLVED_OWNER` to `owner`, `RESOLVED_REPO` to `name`
   - If the call fails → fall back to `DETECTED_OWNER`/`DETECTED_REPO` and warn: "Could not query repo metadata — fork detection skipped."
3. **Owner and repo confirmation**: When a fork was detected, show:
   > Detected fork `<DETECTED_OWNER>/<DETECTED_REPO>` → upstream `<RESOLVED_OWNER>/<RESOLVED_REPO>`.
   > Project will be created under **<RESOLVED_OWNER>** with repo name **<RESOLVED_REPO>**. Confirm or correct.

   When not a fork, show:
   > Detected **<RESOLVED_OWNER>/<RESOLVED_REPO>**. Confirm or correct owner and repo name.

   The user can override either value. After confirmation, use the confirmed values as `OWNER` and `REPO` for all subsequent steps.
4. **Check for existing project**:
   ```bash
   ~/.claude/bin/claude-pm/task-project-list "$OWNER"
   ```
   If this command fails → "Could not list projects for `<OWNER>`. Verify the owner is correct." and stop.
   Check: `jq '.projects[] | select(.title == "<REPO>")'`. If exists → "Project '<REPO>' already exists for <OWNER>. Config file may need to be created manually — check the project in GH UI."
5. Check config file exists: if `~/.config/claude-pm/<DETECTED_REPO>.taskboard.json` exists → "Setup already complete for this repo."

**Steps**:

1. Create project:
   ```bash
   ~/.claude/bin/claude-pm/task-project-create "$OWNER" "$REPO"
   ```
   Extract `number` and `id` from the JSON response.
2. Create Plan field:
   ```bash
   ~/.claude/bin/claude-pm/task-field-create "$PROJECT_NUMBER" "$OWNER" "Plan" "TEXT"
   ```
3. Get the Status field ID:
   ```bash
   ~/.claude/bin/claude-pm/task-field-list "$PROJECT_NUMBER" "$OWNER"
   ```
   Extract with: `jq '.fields[] | select(.name == "Status") | .id'`
4. Configure Status field options:
   ```bash
   ~/.claude/bin/claude-pm/task-status-options-set "$STATUS_FIELD_ID"
   ```
   Extract option IDs from the response.

5. Ensure config directory exists: `mkdir -p ~/.config/claude-pm`

6. Write config to `~/.config/claude-pm/<DETECTED_REPO>.taskboard.json`.
   Use `owner_type` from the fork resolution query (step 2): `"User"` or `"Organization"`.
   ```json
   {
     "project_number": <number>,
     "owner": "<OWNER>",
     "owner_type": "User or Organization",
     "repo": "<REPO>",
     "project_id": "PVT_...",
     "field_ids": {
       "status": "PVTF_...",
       "plan": "PVTF_..."
     },
     "status_option_ids": {
       "Idea": "<hex-id>",
       "Define": "<hex-id>",
       "Design": "<hex-id>",
       "Plan": "<hex-id>",
       "Implement": "<hex-id>",
       "Verify": "<hex-id>",
       "Ship": "<hex-id>",
       "Done": "<hex-id>"
     },
     "available_skills": []
   }
   ```

7. Open the project board:
   ```bash
   URL=$(~/.claude/bin/claude-pm/task-board-url)
   xdg-open "$URL" || open "$URL"
   ```

8. Display setup complete message:

```
Setup complete! Your project has 8 status columns (Idea → Done).

The default view is a table. Use `/task board` to open the board layout,
or switch manually via the View button → Board in the GitHub UI.

Optional: add a "Plan" column to the table view — click "+" in the
column header row → select "Plan". This shows the path to each task's
plan file, linking board items to their living design docs.
```

---

## Subcommand: board

1. Build the board URL:
   ```bash
   URL=$(~/.claude/bin/claude-pm/task-board-url)
   ```
2. Open it: `xdg-open "$URL"` (Linux) or `open "$URL"` (macOS).
3. Confirm: "Opened project board for `<repo>`."

---

## Subcommand: teardown

1. Load config (standard repo detection + config loading). If no config exists, fail with the standard message.
2. Inventory what will be destroyed:
   - Query items:
     ```bash
     ITEMS=$(~/.claude/bin/claude-pm/task-item-list)
     ITEM_COUNT=$(echo "$ITEMS" | jq '.items | length')
     ```
   - Check for plan files: `find plans -name "*.md" 2>/dev/null | wc -l`
   - Config file path
3. Display warning with full inventory:

```
========================================
  TEARDOWN — PERMANENT DESTRUCTION
========================================

This will permanently delete:

  GitHub Project: "<repo>" (owned by <owner>)
    - <N> task items with all session logs
    - All board views, fields, and configuration
    Project URL: <board_url>

  Config file:
    ~/.config/claude-pm/<DETECTED_REPO>.taskboard.json

  Plan files (<X> found):
    plans/001-foo.md
    plans/002-bar.md
    ...

  (or: No plan files found.)

This cannot be undone.

========================================
```

4. If plan files exist, use `AskUserQuestion` asking: "Do you want to include plan files in the teardown?" (Yes/No)
5. Use `AskUserQuestion` for final confirmation. Display the warning text and ask the user to type their response. The ONLY accepted confirmation is the exact phrase: **delete it all**. Any other input aborts with "Teardown aborted."
6. On confirmation, execute in order:
   a. Close all linked issues: extract issue numbers from `$ITEMS` where `content.type == "Issue"`, close each:
      ```bash
      ~/.claude/bin/claude-pm/task-issue-close <number>
      ```
   b. Delete GitHub Project:
      ```bash
      ~/.claude/bin/claude-pm/task-project-delete "$PROJECT_NUMBER" "$OWNER"
      ```
   c. Delete config file: `rm ~/.config/claude-pm/<DETECTED_REPO>.taskboard.json`
   d. If user opted in: delete each plan file listed
   e. If `plans/` directory is now empty, remove it: `rmdir plans 2>/dev/null`
7. Confirm completion:
```
Teardown complete.
  - <N> linked issues closed
  - GitHub Project "<repo>" deleted
  - Config file removed
  - <N> plan files deleted (or: Plan files kept)
```

---

## Subcommand: new

1. Derive a concise title from the description (short, descriptive, no verbs like "Add" or "Implement")
2. Create the issue:
   ```bash
   RESULT=$(echo "## Session Log

   [$(date '+%Y-%m-%d %H:%M')] **Define started**" | ~/.claude/bin/claude-pm/task-issue-create "$TITLE")
   NUMBER=$(echo "$RESULT" | jq -r '.number')
   URL=$(echo "$RESULT" | jq -r '.url')
   ```
3. Add to board:
   ```bash
   ~/.claude/bin/claude-pm/task-item-add "$URL"
   ```
4. Find the item:
   ```bash
   ITEM_ID=$(~/.claude/bin/claude-pm/task-item-find "$NUMBER" | jq -r '.id')
   ```
5. Set status to Define:
   ```bash
   ~/.claude/bin/claude-pm/task-status-set "$ITEM_ID" Define
   ```
6. Ensure `plans/` directory exists: `mkdir -p plans`
7. Create plan file at `plans/<issue_number>-short-title.md` with just the title header:
   ```markdown
   # <Title>
   ```
8. Set Plan field on board item:
   ```bash
   ~/.claude/bin/claude-pm/task-plan-set "$ITEM_ID" "plans/<issue_number>-short-title.md"
   ```
9. Build skill context and invoke:
   ```
   Skill: task-define
   Args:
   Title: <title>
   Issue: <issue_number>
   Repo: <repo>
   Body: |
     ## Session Log
     [<timestamp>] **Define started**
   ```
10. After skill completes (look for `completion` block), update board:
    - Write final plan file content
    - Update body:
      ```bash
      echo "$NEW_BODY" | ~/.claude/bin/claude-pm/task-issue-edit-body "$NUMBER"
      ```
    - Set status to Design:
      ```bash
      ~/.claude/bin/claude-pm/task-status-set "$ITEM_ID" Design
      ```

---

## Subcommand: list

Query the board:
```bash
~/.claude/bin/claude-pm/task-item-list
```

Parse items, group by status in pipeline order: Idea, Define, Design, Plan, Implement, Verify, Ship. Exclude Done (archived). Omit empty statuses. Only include items where `content.type == "Issue"`.

For each item, extract the most recent body log entry (last line matching `[YYYY-MM-DD ...] ...`). Use `content.number` as the issue number.

Display format:
```
## <Status> (<count>)
  #<issue_number>  <title>
      Last: [<date>] <entry>
```

For items in Implement or Verify, extract and show the impl ID if present.

---

## Subcommand: resume

1. If no number provided, use `AskUserQuestion` to ask "Which task number?"
2. Find the item and read the body:
   ```bash
   ITEM=$(~/.claude/bin/claude-pm/task-item-find "$NUMBER")
   BODY=$(~/.claude/bin/claude-pm/task-issue-view "$NUMBER")
   ```
   Extract title, status, plan field, and the project item ID (`id`) from `$ITEM`.
3. Read the plan file if it exists.
4. Get current diff: `jj diff --stat` (if in Implement/Verify/Ship)

Based on status, invoke the appropriate skill:

| Status | Skill | Behavior |
|--------|-------|----------|
| Idea | task-define | Transition to Define first, then start conversation |
| Define | task-define | Resume conversation with existing body context |
| Design | task-design | Resume conversation with existing body context |
| Plan | task-plan | Resume planning with existing body context |
| Implement | task-implement | Resume coding — show briefing with impl ID and criteria progress |
| Verify | task-verify | Re-run verification from the top |
| Ship | task-ship | Continue from where it left off |
| Done | (none) | "Task #N is Done. Would you like to revert to a previous phase?" |

Build the appropriate labeled context block for the skill and invoke it.

After skill completes, handle board updates based on the completion block.

---

## Subcommand: pause

Only valid mid-conversation. If no active task context in the conversation, tell the user there's nothing to pause.

1. Determine current task from conversation context (issue number, title, status, phase)
2. Generate phase-aware pause entry:
   - **Define/Design**: what's been established, what questions remain
   - **Plan**: what's been explored, what's still unmapped
   - **Implement/Verify**: current activity, impl ID, criteria progress, next steps
   - **Ship**: which sub-steps are done, what remains
3. Update the body:
   ```bash
   echo "$UPDATED_BODY" | ~/.claude/bin/claude-pm/task-issue-edit-body "$NUMBER"
   ```
   Append:
   ```
   [<timestamp>] **Paused** (<phase>)
   Working on: <current activity>
   Next: <what to do when resumed>
   <user note if provided>
   ```
4. Task stays at current status. Confirm to user.

---

## Subcommand: note

Parse arguments:
- If first word is a number: `note <number> <text>` — use that issue number
- Otherwise: `note <text>` — use current task from conversation context

If no issue can be determined, ask the user which task number.

Read the current body, append the note, write it back:
```bash
BODY=$(~/.claude/bin/claude-pm/task-issue-view "$NUMBER")
# append: [<timestamp>] **Note**: <user's text verbatim>
echo "$UPDATED_BODY" | ~/.claude/bin/claude-pm/task-issue-edit-body "$NUMBER"
```

The agent may add brief context from the current phase if useful, but keeps it minimal.

---

## Subcommand: abandon

Number is always required.

1. Find the item and read the body:
   ```bash
   ITEM=$(~/.claude/bin/claude-pm/task-item-find "$NUMBER")
   BODY=$(~/.claude/bin/claude-pm/task-issue-view "$NUMBER")
   ```
   Extract title, status, plan field, and the project item ID.
2. Present confirmation:
   - Task number and title
   - Current status and criteria progress (if applicable)
   - Whether a plan file exists (will be deleted)
   - Whether there are uncommitted code changes (`jj diff --stat`)
3. Use `AskUserQuestion` for explicit confirmation
4. On confirmation:
   - Update the body with abandon entry:
     ```bash
     echo "$UPDATED_BODY" | ~/.claude/bin/claude-pm/task-issue-edit-body "$NUMBER"
     ```
   - Delete plan file if it exists
   - Close the issue:
     ```bash
     ~/.claude/bin/claude-pm/task-issue-close "$NUMBER"
     ```
   - Archive the project item:
     ```bash
     ~/.claude/bin/claude-pm/task-item-archive "$ITEM_ID"
     ```
5. Confirm to user.

---

## Board update helpers

### Set status
```bash
~/.claude/bin/claude-pm/task-status-set "$ITEM_ID" "<status_name>"
```

### Set plan field
```bash
~/.claude/bin/claude-pm/task-plan-set "$ITEM_ID" "<plan_path>"
```

### Update body
Read current body, append entry, write back:
```bash
BODY=$(~/.claude/bin/claude-pm/task-issue-view "$NUMBER")
# append new entry
echo "$UPDATED_BODY" | ~/.claude/bin/claude-pm/task-issue-edit-body "$NUMBER"
```

### Post comment
```bash
echo "$COMMENT" | ~/.claude/bin/claude-pm/task-issue-comment "$NUMBER"
```

---

## Skill invocation pattern

Build a labeled text block with the fields the skill expects, then invoke via the `Skill` tool:

```
Skill: task-<phase>
Args:
Title: <title>
Issue: <issue_number>
Repo: <repo>
Plan: <plan_path>
Body: |
  <current body content>
Impl: <impl_id>          (implement/verify only)
Verify: <verify_command>  (implement/verify/ship only)
```

After skill invocation, look for a `completion` fenced block in the conversation. Parse its fields to determine next steps:

```
status: done | paused | regressed | rework
plan: <path>
summary: <one-line>
regress_to: <phase>       (only if status: regressed)
rework: <description>     (only if status: rework)
impl: <impl_id>           (only if implement/verify)
comment: <markdown>       (optional, posted as issue comment)
```

If the completion block contains a `comment` field (multiline, indicated by `comment: |` followed by indented lines), post it as an issue comment before any other updates:

```bash
echo "$COMMENT" | ~/.claude/bin/claude-pm/task-issue-comment "$NUMBER"
```

Based on completion status:
- **done**: Post comment (if present) → update body → advance status to next phase
- **paused**: Update body with pause context, stay at current status
- **regressed**: Post comment (if present) → update body with regression reason → set status to target phase
- **rework**: Post comment (if present) → append "Rework needed impl-N+1: <rework description>" to body → increment impl ID → set status to Implement → re-invoke task-implement with rework context and new impl ID

---

## Phase transition table

| From | To | Board updates |
|------|-----|--------------|
| Define | Design | Append "Define complete", set status Design |
| Design | Plan | Append "Design confirmed", set status Plan |
| Plan | Implement | Append "Plan confirmed", set status Implement |
| Implement | Verify | Append "Implement complete impl-N", set status Verify |
| Verify | Ship | Append "Verify passed impl-N", set status Ship |
| Verify | Implement | Append "Rework needed impl-N+1: reason", set status Implement |
| Ship | Done | Append push details, set status Done, close issue, archive item |
| Any | Earlier | Append "Regressed to <phase>: reason", set status to target |
