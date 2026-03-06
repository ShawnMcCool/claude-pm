---
name: task-verify
description: Skeptical review of implementation — actively look for what's wrong
---

# Task Verify

You are performing a skeptical review of an implementation. Your job is to actively look for things that are wrong, not confirm that things are right. Depth scales with task complexity.

## Input

```
Title: <task title>
Item: <item number>
Repo: <repo name>
Plan: <plan file path>
Impl: <impl-id> (e.g. impl-1)
Verify: <verification command> (e.g. mix precommit)
```

Read the plan file for acceptance criteria and implementation plan.

## Analysis protocol

Six analysis tools available. Use judgment about which are relevant — a one-line fix doesn't need architecture compliance, but a new pipeline stage gets the full treatment.

### Always performed

**1. Fresh verification run**
Run the verification command. Report full output — do not summarize or filter.

**2. Acceptance criteria walkthrough**
For each criterion in the plan file:
- **Status**: met / partially met / not met
- **Evidence**: specific code, test, or behavior that demonstrates it
- **Concerns**: anything that technically passes but feels fragile or incomplete

### Performed when relevant to scope

**3. Diff review**
Read the complete diff (`jj diff`). For each changed file: does it match criteria? Unintended side effects? Consistent with existing patterns? Unhandled edge cases?

**4. Regression check**
Did existing tests change intentionally or collaterally? New warnings? Significant test count changes?

**5. Architecture compliance**
Cross-reference against CLAUDE.md principles, relevant decision records, relevant specs. Flag violations.

**6. Contract compliance**
If the change touches serialization, channels, or wire format: read the relevant spec, verify implementation matches, note spec updates needed for Ship.

## Verification report

Scale to the task:

**Simple task** — short report: test results, criteria status, verdict.

**Complex task** — full report:

```
## Verification Report — <impl-id>

### Test Results
<full output of verification command>

### Acceptance Criteria
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | ... | met | test_foo confirms... |
| 2 | ... | partial | handles happy path but not... |

### Diff Review
<findings per file, if any issues>

### Regression Check
<any changed tests, new warnings, etc.>

### Architecture/Contract Compliance
<any violations or concerns>

### Verdict
<PASS / REWORK NEEDED>
```

## Rework protocol

**Minor fixes** (typos, missing assertion, unused variable, small logic fix):
- Fix inline during Verify. No new implementation ID.
- Re-run verification after fix.
- Note: will be recorded as `Minor fix during verify: <description>`

**Significant rework** (missing edge case, incorrect approach, failed criterion, architectural violation):
- Present the rework scope to the user
- Output completion with rework info — the command will create a new impl ID and transition to Implement

**Regression to earlier phases**: If the entire approach was wrong, flag to the user and ask what to do.

## Completion

**On pass** (user confirms satisfaction):

~~~
```completion
status: done
impl: <impl-id>
plan: <plan file path>
summary: Verification passed — <brief note>
```
~~~

**On rework needed**:

~~~
```completion
status: rework
impl: <current-impl-id>
plan: <plan file path>
rework: <description of what needs fixing>
summary: <one-line>
```
~~~

**On regression**:

~~~
```completion
status: regressed
regress_to: <phase>
plan: <plan file path>
summary: <what was discovered>
```
~~~

## Hard constraints

- MUST produce a verification report — user needs to see findings
- MUST NOT self-advance to Ship — user confirms conversationally
- Significant rework creates a new implementation ID and goes back to Implement
- Each return to Verify runs the full protocol from the top, not just re-checking rework
- Minor fixes are allowed inline but must be noted and re-verified
- Review with skepticism — actively look for what's wrong
