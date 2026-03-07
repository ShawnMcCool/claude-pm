---
name: task-ship
description: Documentation, decision records, cleanup, and push
---

# Task Ship

You are performing the final quality gate before work leaves the repo. Documentation, decision records, cleanup, and push.

## Input

```
Title: <task title>
Issue: <issue number>
Repo: <repo name>
Plan: <plan file path>
Verify: <verification command> (e.g. mix precommit)
```

Read the plan file and the diff (`jj diff --stat`, `jj diff`) to understand the full scope of changes.

## Step 1: Documentation

Determine what needs updating from the diff:

| Diff touches... | Check... |
|-----------------|----------|
| Ash resources (new attributes/relationships) | `specs/DATA-FORMAT.md` — wire format change? |
| Channel modules (new messages) | `specs/API.md` — **must update** |
| Pipeline/Broadway | `PIPELINE.md` — stage descriptions |
| LiveView/LiveComponent | `DESIGN.md` — page inventory |
| Config modules (new key) | `defaults/backend.toml` — **must add** |
| Image modules | `specs/IMAGE-CACHING.md`, `specs/IMAGE-SIZING.md` |
| Playback/mpv | `specs/PLAYBACK.md` |
| New dependency | `CLAUDE.md` if it adds architectural concept |

If no docs need updating, explicitly state: "Documentation check: no contract or interface changes detected."

Update any docs that need it.

## Step 2: Decision records

ADRs for significant design decisions were created at the start of Implement. During Ship:

1. Verify existing ADRs are still accurate after implementation
2. Ask the user about any new decisions that emerged during implementation or verification — patterns established, alternatives rejected, constraints discovered
3. Create new ADRs if warranted. Format: MADR 4.0 lean in `decisions/<category>/`.

## Step 3: Cleanup

Scope: files changed in this task + systems deprecated by this task. Not a full codebase audit.

**Backend (Elixir)**:

| Artifact | Action |
|----------|--------|
| `IO.inspect` | Remove all |
| `dbg()` | Remove all |
| Raw Logger.debug/info | Remove (keep `Log.info(:component, ...)`) |
| TODOs not in TODO.md | Remove |
| Deprecated code paths | Clean up dead code |
| Unused aliases/imports | Fix (`mix compile --warnings-as-errors`) |
| Temp files in `tmp/` | Remove task-created files |

**Rust repos**:

| Artifact | Action |
|----------|--------|
| `println!`/`eprintln!` | Remove (except CLI error paths) |
| `dbg!` | Remove all |
| TODOs not tracked | Remove |
| Deprecated code paths | Clean up |
| Clippy warnings | Fix all |
| Formatting | `cargo fmt` |

Post-cleanup: re-run the verification command. If cleanup cascades (removing debug → unused variable → remove variable), fix the cascade.

If cleanup reveals significant refactoring scope, flag to the user — may need to regress to Implement.

## Step 4: Push (Jujutsu workflow)

**Determine conventional commit prefix from diff:**

| Change type | Prefix |
|-------------|--------|
| New feature/behavior | `feat:` |
| Bug fix | `fix:` |
| Restructuring | `refactor:` |
| Performance | `perf:` |
| Tests only | `test:` |
| Docs only | `docs:` |
| Build/deps/config | `chore:` |

Format: lowercase after prefix, max 72 chars, present tense imperative, describe what not how.

**Splitting**: Automatically split when the diff has clearly distinct purposes. Don't split tightly coupled changes (feature + its tests). Use `jj split -m "<desc>" <files>` for file-level splits. Handle splits without involving the user.

**Push sequence** (per change, after any splits):
```bash
jj describe -m "<message>"
jj new
jj bookmark set main -r @-
jj git push --bookmark main
```

Error handling: bookmark conflict → `jj git fetch` + rebase. Network error → retry. Never force-push main.

## Phase confirmation

Present the ship summary:
- What was pushed (descriptions and commit hashes)
- Docs updated
- Decision records created/verified
- Cleanup performed

Ask if the user is satisfied. User confirms conversationally.

## Completion

When the user confirms:

~~~
```completion
status: done
plan: <plan file path>
summary: Shipped — <descriptions and short hashes>
comment: |
  ## Ship Summary

  ### Pushed
  - `<hash>` <description>

  ### Documentation
  - <docs updated or "no changes needed">

  ### Decision Records
  - <ADRs created/verified or "none">

  ### Cleanup
  - <what was cleaned>
```
~~~

## Hard constraints

- No skipping docs, decision records, or cleanup
- Re-run verification after cleanup
- If cleanup reveals significant rework scope, output `status: regressed` with `regress_to: Implement`
- Splits are automated — don't ask the user about split decisions
- If the user wants to pause, output completion with `status: paused` and note which sub-steps are done
