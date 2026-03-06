---
description: Task pipeline — manage development tasks through GitHub Projects
allowed-tools: Bash, Read, Glob, Grep, Write, Edit, AskUserQuestion, Skill
---

You are orchestrating a development task through a GitHub Projects pipeline. You handle all board I/O and delegate phase work to skills.

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

## Body editing pattern

`gh project item-edit` replaces the full body. To append:
1. Read current body (from item query)
2. Append new entry
3. Write body via temp file to avoid shell quoting issues:

```bash
BODY="$(cat <<'BODYEOF'
<full body content>
BODYEOF
)"
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --body "$BODY"
```

For long bodies, write to a temp file and use `--body "$(cat /tmp/task_body.tmp)"`.

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

1. Check `gh` CLI installed: `which gh`. If missing → "Install the GitHub CLI: https://cli.github.com/"
2. Check auth: `gh auth status`. If not authenticated → "Run `gh auth login` first."
3. **Project scope check**: Parse `gh auth status` output for the `project` scope (which implies `read:project`). If missing:
   - Warn the user: "Missing project scope. This will print a URL and code — open the URL in your browser and enter the code to authorize."
   - Run: `gh auth refresh -h github.com -s project`
4. **Fork resolution**: Query the GitHub API to check if the detected repo is a fork:
   ```bash
   gh api "repos/$DETECTED_OWNER/$DETECTED_REPO" --jq '{
     name: .name,
     owner: .owner.login,
     owner_type: .owner.type,
     is_fork: .fork,
     parent_owner: .parent.owner.login,
     parent_name: .parent.name
   }'
   ```
   - If `is_fork` is true → set `RESOLVED_OWNER` to `parent_owner`, `RESOLVED_REPO` to `parent_name`
   - If not a fork → set `RESOLVED_OWNER` to `owner`, `RESOLVED_REPO` to `name`
   - If the API call fails (404, network error) → fall back to `DETECTED_OWNER`/`DETECTED_REPO` and warn: "Could not query repo metadata — fork detection skipped."
5. **Owner and repo confirmation**: When a fork was detected, show:
   > Detected fork `<DETECTED_OWNER>/<DETECTED_REPO>` → upstream `<RESOLVED_OWNER>/<RESOLVED_REPO>`.
   > Project will be created under **<RESOLVED_OWNER>** with repo name **<RESOLVED_REPO>**. Confirm or correct.

   When not a fork, show:
   > Detected **<RESOLVED_OWNER>/<RESOLVED_REPO>**. Confirm or correct owner and repo name.

   The user can override either value. After confirmation, use the confirmed values as `OWNER` and `REPO` for all subsequent steps.
6. **Check for existing project**: Run `gh project list --owner <OWNER> --format json`. If this command fails (e.g. "unknown owner type"), surface a clear message: "Could not list projects for `<OWNER>`. Verify the owner is correct." and stop. Otherwise, check: `jq '.projects[] | select(.title == "<REPO>")'`. If exists → "Project '<REPO>' already exists for <OWNER>. Config file may need to be created manually — check the project in GH UI."
7. Check config file exists: if `~/.config/claude-pm/<DETECTED_REPO>.taskboard.json` exists → "Setup already complete for this repo."

**Steps**:

1. Create project: `gh project create --owner <OWNER> --title "<REPO>" --format json`
2. Extract project number and ID from the response
3. Create Plan field: `gh project field-create <project_number> --owner <OWNER> --name "Plan" --data-type TEXT --format json`
4. Get the Status field ID:
   ```bash
   gh project field-list <project_number> --owner <OWNER> --format json | jq '.fields[] | select(.name == "Status")'
   ```
5. Configure Status field options via GraphQL (the CLI cannot edit single-select options directly).
   Valid colors: GRAY, BLUE, GREEN, YELLOW, ORANGE, RED, PINK, PURPLE.
   ```bash
   gh api graphql -f query='
     mutation {
       updateProjectV2Field(input: {
         fieldId: "<STATUS_FIELD_ID>"
         singleSelectOptions: [
           {name: "Idea",      color: GRAY,   description: ""},
           {name: "Define",    color: BLUE,   description: ""},
           {name: "Design",    color: PURPLE, description: ""},
           {name: "Plan",      color: ORANGE, description: ""},
           {name: "Implement", color: YELLOW, description: ""},
           {name: "Verify",    color: GREEN,  description: ""},
           {name: "Ship",      color: RED,    description: ""},
           {name: "Done",      color: PINK,   description: ""}
         ]
       }) {
         projectV2Field {
           ... on ProjectV2SingleSelectField {
             options { id name }
           }
         }
       }
     }
   '
   ```
   Extract option IDs directly from the mutation response.

6. Ensure config directory exists: `mkdir -p ~/.config/claude-pm`

7. Write config to `~/.config/claude-pm/<DETECTED_REPO>.taskboard.json`.
   Use `owner_type` from the fork resolution query (step 4): `"User"` or `"Organization"`.
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

8. Open the project in the browser: `gh project view <project_number> --owner <OWNER> --web`

9. Display setup complete message:

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

1. Load config (standard repo detection + config loading). If no config exists, fail with the standard message.
2. Build the board URL based on `owner_type`:
   - Organization: `https://github.com/orgs/<owner>/projects/<project_number>?layout=board`
   - User: `https://github.com/users/<owner>/projects/<project_number>?layout=board`
3. Open it: run `open <url>` (macOS) or `xdg-open <url>` (Linux).
4. Confirm: "Opened project board for `<repo>`."

---

## Subcommand: teardown

1. Load config (standard repo detection + config loading). If no config exists, fail with the standard message.
2. Inventory what will be destroyed:
   - Query GitHub Project to get item count: `gh project item-list <project_number> --owner <owner> --format json --limit 100 | jq '.items | length'`
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
    Project URL: https://github.com/users/<owner>/projects/<number>
    (use /orgs/ instead of /users/ when owner_type is "Organization")

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
   a. Delete GitHub Project: `gh project delete <project_number> --owner <owner> --format json`
   b. Delete config file: `rm ~/.config/claude-pm/<DETECTED_REPO>.taskboard.json`
   c. If user opted in: delete each plan file listed
   d. If `plans/` directory is now empty, remove it: `rmdir plans 2>/dev/null`
7. Confirm completion:
```
Teardown complete.
  - GitHub Project "<repo>" deleted
  - Config file removed
  - <N> plan files deleted (or: Plan files kept)
```

---

## Subcommand: new

1. Derive a concise title from the description (short, descriptive, no verbs like "Add" or "Implement")
2. Create draft item:
   ```bash
   gh project item-create <project_number> --owner <owner> --title "<title>" --format json
   ```
3. Extract item ID from response
4. Set status to Define:
   ```bash
   gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$STATUS_FIELD_ID" --single-select-option-id "$DEFINE_OPTION_ID"
   ```
5. Initialize body:
   ```
   ## Session Log

   [<timestamp>] **Define started**
   ```
6. Determine plan file number: `find plans -name "*.md" 2>/dev/null`, take max number + 1, zero-pad to 3
7. Create plan file at `plans/NNN-short-title.md` with just the title header:
   ```markdown
   # <Title>
   ```
8. Set Plan field on board item:
   ```bash
   gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$PLAN_FIELD_ID" --text "plans/NNN-short-title.md"
   ```
9. Build skill context and invoke:
   ```
   Skill: task-define
   Args:
   Title: <title>
   Item: <item_number>
   Repo: <repo>
   Body: |
     ## Session Log
     [<timestamp>] **Define started**
   ```
10. After skill completes (look for `completion` block), update board:
    - Write final plan file content
    - Append `[<timestamp>] **Define complete** <summary>` to body
    - Set status to Design

---

## Subcommand: list

Query the board:
```bash
gh project item-list <project_number> --owner <owner> --format json --limit 100
```

Parse items, group by status in pipeline order: Idea, Define, Design, Plan, Implement, Verify, Ship. Exclude Done (archived). Omit empty statuses.

For each item, extract the most recent body log entry (last line matching `[YYYY-MM-DD ...] ...`).

Display format:
```
## <Status> (<count>)
  #<number>  <title>
      Last: [<date>] <entry>
```

For items in Implement or Verify, extract and show the impl ID if present.

---

## Subcommand: resume

1. If no number provided, use `AskUserQuestion` to ask "Which task number?"
2. Query the item:
   ```bash
   gh project item-list <project_number> --owner <owner> --format json --limit 100 | jq '.items[] | select(...)'
   ```
   Find the item by number. Extract title, status, body, plan field.
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

1. Determine current task from conversation context (item number, title, status, phase)
2. Generate phase-aware pause entry:
   - **Define/Design**: what's been established, what questions remain
   - **Plan**: what's been explored, what's still unmapped
   - **Implement/Verify**: current activity, impl ID, criteria progress, next steps
   - **Ship**: which sub-steps are done, what remains
3. Append to body:
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
- If first word is a number: `note <number> <text>` — use that item number
- Otherwise: `note <text>` — use current task from conversation context

If no item can be determined, ask the user which task number.

Append to body:
```
[<timestamp>] **Note**: <user's text verbatim>
```

The agent may add brief context from the current phase if useful, but keeps it minimal.

---

## Subcommand: abandon

Number is always required.

1. Query the item to get title, status, plan field, body
2. Present confirmation:
   - Task number and title
   - Current status and criteria progress (if applicable)
   - Whether a plan file exists (will be deleted)
   - Whether there are uncommitted code changes (`jj diff --stat`)
3. Use `AskUserQuestion` for explicit confirmation
4. On confirmation:
   - Append `[<timestamp>] **Abandoned** <reason if provided>` to body
   - Delete plan file if it exists
   - Archive the item:
     ```bash
     gh project item-archive <project_number> --owner <owner> --id "$ITEM_ID"
     ```
5. Confirm to user.

---

## Board update helpers

### Set status
```bash
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$STATUS_OPTION_IDS[<status>]"
```

### Set plan field
```bash
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$PLAN_FIELD_ID" \
  --text "<plan_path>"
```

### Append to body
Read current body → append → write back (see body editing pattern above).

---

## Skill invocation pattern

Build a labeled text block with the fields the skill expects, then invoke via the `Skill` tool:

```
Skill: task-<phase>
Args:
Title: <title>
Item: <item_number>
Repo: <repo>
Plan: <plan_path>
Body: |
  <current body content>
Impl: <impl_id>          (implement/verify only)
Verify: <verify_command>  (implement/verify/ship only)
```

After skill invocation, look for a `completion` fenced block in the conversation. Parse its fields to determine next steps:

```
status: done | paused | regressed
plan: <path>
summary: <one-line>
regress_to: <phase>       (only if status: regressed)
rework: <description>     (only if rework needed)
impl: <impl_id>           (only if implement/verify)
```

Based on completion status:
- **done**: Update body, advance status to next phase
- **paused**: Update body with pause context, stay at current status
- **regressed**: Update body with regression reason, set status to target phase

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
| Ship | Done | Append push details, set status Done, archive item |
| Any | Earlier | Append "Regressed to <phase>: reason", set status to target |
