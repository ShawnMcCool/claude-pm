---
name: task-plan
description: Plan HOW to implement — codebase exploration, concrete steps, test strategy
---

# Task Plan

You are planning how to implement a designed solution. The plan file already has Problem Statement, Approach, and Acceptance Criteria. Your job is to explore the actual codebase and produce a concrete, executable implementation plan.

## Input

```
Title: <task title>
Issue: <issue number>
Repo: <repo name>
Plan: <plan file path>
Body: |
  <current board body>
```

Read the plan file to get the full context. If Body contains prior planning context, pick up where you left off.

## Codebase exploration

Invoke relevant thinking skills (from the repo's `available_skills` config) and read the actual source files that will be affected.

What you're looking for:
- **Files to modify**: Read them, understand their current structure and patterns
- **Reusable code**: Existing functions, utilities, helpers that do what we need or nearly so — don't propose building what already exists
- **Test infrastructure**: Which factory functions exist? Which need to be created? What test patterns does this area use?
- **Precedent**: How were similar features implemented? Follow established patterns.

## Implementation plan

Extend the plan file with `## Implementation Plan`:

```markdown
## Implementation Plan

### Test strategy
- Existing factory functions to use: <list>
- New factory functions needed: <list>
- Test type: <pure function / resource / channel>
- Key assertions: <what the tests prove>

### Order of changes
1. <first change>
2. <second change>
...

### Files to modify
- `path/to/file.ex` — <brief description of changes>

### New files
- <if any, or "(none)">

### Technical decisions
- <implementation-level choices>
```

Test strategy is listed first because it drives the order (test-first mandate).

The **order of changes** is the critical section — it's what makes Implement high-autonomy. If the order is wrong or incomplete, Implement stalls.

## Design invalidation

If exploration reveals the design won't work (assumed module doesn't exist, undiscovered constraint, etc.), flag this to the user and ask what they want to do. If the user wants to regress:

~~~
```completion
status: regressed
regress_to: Design
summary: <what was discovered that invalidates the design>
```
~~~

## Phase confirmation

Summarize: test strategy, order of changes, files to modify, key technical decisions. Ask if the user is satisfied and ready to move to Implement. User confirms conversationally.

## Completion

When the user confirms:

~~~
```completion
status: done
plan: <plan file path>
summary: <one-line summary of the implementation plan>
```
~~~

## Hard constraints

- MUST explore the actual codebase — don't guess at file paths or patterns
- MUST identify reusable code — don't propose building what already exists
- MUST NOT write implementation code during Plan
- The order of changes must be concrete enough that the agent can execute it with high autonomy
- If the user wants to pause, output completion with `status: paused`
