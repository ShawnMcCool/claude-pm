---
name: task-implement
description: Write the code — execute the implementation plan with high autonomy
---

# Task Implement

You are writing code to implement a planned solution. The plan file has the full context: Problem Statement, Approach, Acceptance Criteria, and Implementation Plan with an ordered list of changes.

## Input

```
Title: <task title>
Item: <item number>
Repo: <repo name>
Plan: <plan file path>
Body: |
  <current board body>
Impl: <impl-id> (e.g. impl-1, impl-2)
Verify: <verification command> (e.g. mix precommit)
```

Read the plan file. Check the Body for prior progress on this impl ID.

## Briefing

On entry or resume, present a brief status update:

```
## Task: <title> (#<number>)
**Status**: Implement (<impl-id>) | **Plan**: <plan path>

### Acceptance Criteria
<current checkbox state from plan>

### Implementation Plan
<summary of order of changes>
```

If resuming, add:
```
### Last Session
<most recent body entries>
```

If impl-2+, add:
```
### Rework Scope
<rework description from body>
```

Also show `jj diff --stat` if there are existing changes.

## Step 1: Decision records (impl-1 only)

Before any code, write formal ADRs for significant design decisions from the plan's `## Design Decisions` section. Format: MADR 4.0 lean in `decisions/<category>/`. Not every decision warrants an ADR — only those that establish new patterns, choose between meaningful alternatives, or supersede existing decisions. If none warrant ADRs, skip this step.

Rework passes (impl-2+) skip this step.

## Step 2: Implement

Work through the implementation plan autonomously:

- Follow the order of changes — may deviate if it makes sense, but the plan is the default path
- **Test-first** per the project's testing policy
- Write code, run tests incrementally
- **Check off** acceptance criteria in the plan file as completed
- Report progress but do NOT wait for user acknowledgement at each step

**Intervene/report to the user when:**
- Something goes wrong (test failures you can't resolve, unexpected behavior)
- A decision needs to be made that wasn't covered in the plan
- A criterion is ambiguous and needs clarification
- The implementation reveals the plan was wrong or incomplete
- The verification command fails repeatedly and self-diagnosis isn't working

Do not spin on failures silently. If a fix attempt doesn't work, escalate rather than looping.

## Phase confirmation

When implementation is complete:

1. Walk through each acceptance criterion — all addressed?
2. Run the verification command
3. If verification fails: attempt to diagnose and fix. If the fix doesn't resolve it, tell the user what's happening and ask for guidance.
4. Summarize what was implemented, which criteria are checked off, and the verification result
5. Ask if the user is satisfied and ready to move to Verify

## Completion

When the user confirms:

~~~
```completion
status: done
plan: <plan file path>
impl: <impl-id>
summary: <one-line summary of what was implemented>
```
~~~

## Hard constraints

- No skipping criteria
- No proposing transition if verification fails
- Escalate to user if self-fix fails rather than looping
- If the user wants to pause, output completion with `status: paused` and include impl ID and criteria progress
- If the plan is wrong/incomplete, output completion with `status: regressed` and `regress_to: Plan` (or earlier)
