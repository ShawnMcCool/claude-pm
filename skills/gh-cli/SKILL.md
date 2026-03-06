# gh-cli

Reference for GitHub CLI (`gh`) patterns that trip up automation — auth scopes, non-interactive terminals, owner detection, and GraphQL project mutations.

## Auth scope management

Check current scopes:

```bash
gh auth status
```

The output includes a `Token scopes:` line. Parse it to check for specific scopes.

To add project-related scopes:

```bash
gh auth refresh -h github.com -s read:project -s project
```

The `-h github.com` flag is **required** in non-interactive terminals (e.g. Claude Code's Bash tool). Without it, `gh auth refresh` prompts for a hostname and hangs.

## Non-interactive terminal (device flow)

When `gh auth refresh` or `gh auth login` runs in a non-interactive terminal, GitHub falls back to the **device flow**: it prints a URL and a one-time code, then waits for the user to complete auth in a browser.

**The browser does NOT open automatically.** Always warn the user before running auth commands:

> This will print a URL and code. Open the URL in your browser and enter the code to authorize.

After the user completes the flow in the browser, the CLI unblocks and continues.

## Owner detection

Extract owner and repo from the remote URL (works for both SSH and HTTPS):

```bash
REMOTE_URL=$(jj git remote list 2>/dev/null | head -1 | awk '{print $2}')
# or for plain git:
# REMOTE_URL=$(git remote get-url origin)

OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|.*github\.com[:/]||;s|\.git$||')
DETECTED_OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
DETECTED_REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)
```

**Important:** The detected owner from the remote may be a personal fork, not the org that owns the GitHub Project. Always confirm with the user:

> Detected owner: `<DETECTED_OWNER>`. Is this correct, or should I use a different org/user?

## GraphQL for project fields

The `gh` CLI cannot edit single-select field options directly. Use the GraphQL API to set options on a Status (or any single-select) field.

### Update single-select options

```bash
gh api graphql -f query='
  mutation {
    updateProjectV2Field(input: {
      projectId: "<PROJECT_ID>"
      fieldId: "<FIELD_ID>"
      dataType: SINGLE_SELECT
      singleSelectOptions: [
        {name: "Idea",      color: GRAY,   description: ""},
        {name: "Define",    color: BLUE,   description: ""},
        {name: "Design",    color: PURPLE, description: ""},
        {name: "Plan",      color: ORANGE, description: ""},
        {name: "Implement", color: YELLOW, description: ""},
        {name: "Verify",    color: LIME,   description: ""},
        {name: "Ship",      color: GREEN,  description: ""},
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

The mutation response includes the option IDs — extract them directly, no separate read-back query needed.

### Available colors

`GRAY`, `BLUE`, `GREEN`, `YELLOW`, `ORANGE`, `RED`, `PINK`, `PURPLE`, `LIME`

### Read back field options (verification)

```bash
gh project field-list <NUMBER> --owner <OWNER> --format json \
  | jq '.fields[] | select(.name == "Status") | .options'
```

## Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gh auth refresh` hangs | Missing `-h github.com` in non-interactive terminal | Add `-h github.com` |
| `could not create project` | Missing `project` scope | `gh auth refresh -h github.com -s project` |
| `could not read project` | Missing `read:project` scope | `gh auth refresh -h github.com -s read:project` |
| `project not found` for org | Owner is personal user, not the org | Use correct org name as owner |
| `field-create` can't set options | CLI doesn't support single-select option editing | Use GraphQL `updateProjectV2Field` mutation |
| Device flow code not entered | User wasn't warned, browser didn't open | Warn user before running auth commands |
