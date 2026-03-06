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
| (empty or unrecognized) | help | (none) |

## Repo detection

Detect the current repo:

```bash
if [ -d ".jj" ]; then
  jj git remote list 2>/dev/null | head -1 | sed 's|.*/||;s|\.git$||'
elif [ -d "../.jj" ]; then
  (cd .. && jj git remote list 2>/dev/null | head -1 | sed 's|.*/||;s|\.git$||')
fi
```

Load config from `~/.config/claude-pm/<repo>.taskboard.json`. If missing, fail with: "No taskboard configured for this repo. Run `/task setup` first."

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
```

---

## Subcommand: setup

**Pre-flight checks** (fail gracefully with guidance at each step):

1. Check `gh` CLI installed: `which gh`. If missing → "Install the GitHub CLI: https://cli.github.com/"
2. Check auth: `gh auth status`. If not authenticated → "Run `gh auth login` first."
3. Check for existing project: `gh project list --owner <owner> --format json | jq '.projects[] | select(.title == "<repo>")'`. If exists → "Project '<repo>' already exists for <owner>. Config file may need to be created manually — check the project in GH UI."
4. Check config file exists: if `~/.config/claude-pm/<repo>.taskboard.json` exists → "Setup already complete for this repo."

**Steps**:

1. Warn user: "This may open a browser for GitHub re-authentication."
2. `gh auth refresh -s read:project -s project`
3. Create project: `gh project create --owner <owner> --title "<repo>" --format json`
4. Extract project number and ID from the response
5. Create Plan field: `gh project field-create <project_number> --owner <owner> --name "Plan" --data-type TEXT --format json`
6. Configure Status field options. Get the Status field ID:
   ```bash
   gh project field-list <project_number> --owner <owner> --format json | jq '.fields[] | select(.name == "Status")'
   ```
   The default Status field comes with "Todo", "In Progress", "Done". We need to delete those and create our 8 statuses. Use `gh project field-create` or `gh api` as needed to set:
   `Idea`, `Define`, `Design`, `Plan`, `Implement`, `Verify`, `Ship`, `Done`

   **Note**: The `gh` CLI may not support editing single-select options directly. If so, tell the user to configure the Status field manually in the GH Project Settings UI with the 8 values in order, then re-run `/task setup` to read back the IDs.

7. Read back all IDs:
   ```bash
   gh project field-list <project_number> --owner <owner> --format json
   ```
   Extract field IDs and status option IDs.

8. Write config to `~/.config/claude-pm/<repo>.taskboard.json`:
   ```json
   {
     "project_number": <number>,
     "owner": "<owner>",
     "repo": "<repo>",
     "project_id": "PVT_...",
     "field_ids": {
       "status": "PVTF_...",
       "plan": "PVTF_..."
     },
     "status_option_ids": {
       "Idea": "PVTSSF_...",
       "Define": "PVTSSF_...",
       "Design": "PVTSSF_...",
       "Plan": "PVTSSF_...",
       "Implement": "PVTSSF_...",
       "Verify": "PVTSSF_...",
       "Ship": "PVTSSF_...",
       "Done": "PVTSSF_..."
     },
     "available_skills": []
   }
   ```

9. Tell user to configure views manually in GH UI:
   - **Board view**: columns in pipeline order (Idea → Done)
   - **Table view**: Title, Status, Plan columns

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
6. Determine plan file number: count existing `plans/*.md` files, take max number + 1, zero-pad to 3
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
