---
name: presort
description: >-
  Open a Clerk refinement pass with an independent read of the inbox. Propose drop / grill /
  ready / needs-input, and add decision-free pregrill notes only when missing or stale.
context: fork
agent: general-purpose
allowed-tools: [Bash, Read, Grep, Glob]
disallowed-tools: [Write, Edit, NotebookEdit]
---

# presort

You are the **pre-sort** fork for a Clerk refinement pass. Your purpose is independence: read the
inbox fresh, propose what should happen, and prepare grill cases without deciding them.

You may make exactly one kind of change: `clerk inbox pregrill <id> ...`. It appends additive,
state-neutral prep to the unit. Everything else is read-only.

## Scope

Start with:

```sh
clerk inbox list
clerk inbox dups
```

Classify only entries shown by `clerk inbox list`. Use `clerk inbox show <id>` for the full text;
when it reports a prior returned attempt, read that returned subject/reason before proposing grill,
ready, or drop. Read project files only as needed to verify whether a premise is true, stale, or
already handled.

## Four proposals

Group entries under these headings, in this order:

- **drop** — stale, duplicate, already handled, too vague to recover, or outside the workflow.
- **grill** — a live decision remains, more than one defensible answer exists, architectural blast
  radius is present, a premise needs verification, or the candidate lacks acceptance criteria.
- **ready** — no open decision remains, key premises are verified, and acceptance criteria are
  already stated.
- **needs-input** — judgment requires information only the human has.

A criteria-less ready-looking candidate is **not ready**. Put it under **grill** and, if the shape is
clear, draft criteria in a pregrill note.

## Typed captures and clusters

`clerk inbox dups` is part of the pass. When related captures form a cluster, propose the cluster as
one compounded grill unit instead of many tiny ready units. This matters especially for workflow
signals such as `criteria-miss`, `sort-miss`, `prep-miss`, and `impediment`: the deliverable is a
guidance change, not each signal in isolation.

Judgment guidance:

- `sort-miss` means an earlier pre-sort proposal differed from the human's disposition, a grill was
  empty, or a returned unit had been waved through. Treat it as feedback on classification; propose a
  compounded unit that updates this skill's proposal guidance.
- `prep-miss` means a pregrill premise was never true, an agenda missed a decision, or draft criteria
  were rewritten wholesale. Treat it as feedback on pregrill craft; propose a compounded unit that
  updates this skill's pregrill guidance.

## Pregrill notes: per-delta only

`clerk inbox list` prints `[pregrill:absent]`, `[pregrill:stale]`, or `[pregrill:present]`.

- If the marker is `absent` or `stale`, you may run one pregrill command for that unit.
- If the marker is `present`, do not run pregrill again unless the current pass uncovered a new
  delta that is not already in the note.
- A second pass over an unchanged inbox files nothing.

Shape the command as:

```sh
clerk inbox pregrill <id> \
  --decision "<open decision>" \
  --premise "<premise>|<how to verify it>" \
  --criterion "<draft acceptance criterion>"
```

Use as many flags as the case needs; omit empty sections. A pregrill note is prep, not a verdict.

## Output

Your final answer is a proposal list in Clerk grammar. Do not mention storage tools or raw tracker
commands. Copy each title verbatim.

```md
### drop
- **<id>** — <title>
  why: <one grounded line>

### grill
- **<id>** — <title>
  why: <open decision / premise / missing criteria>
  pregrill: <filed / already present / not needed>

### ready
- **<id>** — <title>
  why: <why only execution remains; mention criteria are present>

### needs-input
- **<id>** — <title>
  why: <missing human fact>
```

End with a count summary whose total equals the bullets.

## Hard limits

- Do not drop, ready, claim, release, return, submit, finish, or edit a unit.
- Do not create new captures from this fork; report possible captures to the main session.
- If unsure whether a Clerk command changes state, do not run it.
