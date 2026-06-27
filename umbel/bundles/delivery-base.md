---
name: delivery-base
description: The delivery System — the invariant contract every delivery method shares (consume one ready unit by tier, claim it, capture-and-escalate never deciding inline, mark it done) plus the common delivery tooling (plan/PR review, decision-writing, tuidriver). Not run alone; a method like `delivery-superpowers` extends it and adds how to prep + build.
skills:
  - plannotator/annotate
  - plannotator/last
  - pocock/grill-with-docs
  - local/glean
mcps:
  - local/tuidriver
hooks:
  - local/delivery-base-ruleset
---

# delivery-base

The **invariant half** of delivery. `discovery` produces a ready backlog; a **delivery
method** drives one ready unit to a shipped change. Everything *common to every method*
lives here — the lifecycle contract and the shared tooling — so methods
(`delivery-superpowers`, and future ones) swap without touching it.

Not run on its own; a method bundle does `extends: [delivery-base, …]`.

## The contract (injected each session)

A SessionStart hook (`delivery-base-ruleset`) injects the tier-selected contract
(`seed.public.md` / `seed.private.md`, chosen by the committed `.repo-visibility`
marker): **scope in** one unit → **claim** it → **capture-and-escalate, never decide
inline** → **mark done** (+ a review gate on public). That law holds regardless of which
method runs between claim and done. Branching strategy, prep, execution, and whether/how
decisions get recorded belong to the **method**, not here.

## Shared tooling

- `plannotator/annotate` + `plannotator/last` — review a plan or a long thread.
- `pocock/grill-with-docs` — stress-test a design and write a decision record (a method
  decides *whether/how* to record; the tool lives here).
- `local/glean` — end-of-session harvester (`/glean`): a fork re-reads the session transcript
  and files the Impediments the agent hit but never captured. Track-agnostic, so it lives in the
  base layer; dual-listed in `discovery`.
- `local/tuidriver` (MCP) — drive a terminal UI to verify behaviour.

## Applying

Same tier setup as discovery: record `public`/`private` in a committed one-line
`.repo-visibility` at the repo root (shared with discovery — reuse it if present). The
contract hook reads it each session.

Tooling prerequisites: `plannotator` on PATH (the `annotate`/`last` skills shell out to it)
and the `tuidriver` MCP runtime — alongside `gh` (public PRs) and `bd` (private claim/close).

beads (used for private-tier claim/close) is wired by discovery's **"Wire beads"** step —
Dolt-remote-backed on the git origin (`bd dolt push` → `refs/dolt/data`), with beads' config
+ portable hook shims committed and the DB/export/logs gitignored, and `bd bootstrap` on a
fresh clone. `issues.jsonl` is an export, **never** the git backing. Install hooks with
`bd hooks install --beads` so they work across the worktrees delivery methods create.
