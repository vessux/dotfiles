---
status: accepted
---

# Glean — a retrospective session-harvest fork that *writes* typed captures (impediments first)

Ambient capture is a standing rule on both tracks ("the moment any bug or follow-up surfaces,
`bd create` it"), yet the agent routinely fails to capture its *own* workflow friction: an error
interrupts a task mid-stride, the agent routes around it, and the friction is never filed. This is
a **focus failure, not a ritual failure** — the agent is optimised to finish the task, so it is an
unreliable witness to its own session. The cost is paid every session: the same harness roadblock
(the worktree teardown that fails on every delivery finish; a denied permission; a confusing tool
retried three times) is re-hit and re-routed-around, never fixed, because it never reaches the
backlog where a fix could be decided. **Glean** is the retrospective counterpart to ambient
capture that recovers exactly these missed signals.

## Decision

A single canonical skill — **`/glean`** — gleans a finished session for *compounding signals* and
files each as a typed Capture. It is the first concrete instance of a **compound-engineering**
discipline: each session leaves leverage that cheapens the next.

- **Ground truth is the transcript, not the agent's memory.** The whole premise is that the
  agent's in-context view is the lossy, biased witness we are working around (and compaction has
  often already summarised the tool errors away). `/glean` reads the session **transcript JSONL**,
  which retains every `is_error`, permission denial, and retry verbatim and survives compaction.
- **The session is the *main thread plus every subagent* — not just the main file.** Subagent
  (fork) transcripts are stored as **separate files**, `<slug>/<uuid>/subagents/agent-<id>.jsonl`,
  each with an `agent-<id>.meta.json` sidecar (`{agentType, description, toolUseId}`). A main-only
  scan is blind to them — and that is where delivery's friction concentrates, because delivery runs
  `dispatching-parallel-agents` / `subagent-driven-development` (one observed session: 42 subagent
  files, 18 `is_error` results inside them, none in the main thread). So `/glean` reads the main
  transcript **and** all of the session's subagent transcripts, attributing each impediment via the
  `.meta.json` (which subagent, doing what). Transcripts are located by **UUID discovery**, not by
  constructing a slug: worktrees get their own project slug (`…-repo--worktrees-<branch>`), so a
  delivery session working in `.worktrees/` lives under that slug, and discovering by `<uuid>`
  finds the main + subagent set wherever it sits. (Cross-*session* correlation is out of scope —
  glean is per-session by design; that is Gap B.)
- **A fork does the reading — but unlike `presort`, it *writes*.** Like `presort` (ADR 0007) the
  scan runs as a disinterested fork: a fresh agent re-reading the raw record is not anchored to the
  main agent's "I handled that fine" narrative, and parsing a large JSONL stays out of the main
  context. The deliberate divergence is that `presort` is read-only and Glean's fork **creates beads
  directly**. The reason is structural: `presort` gates **refinement**, where the refiner has a
  wave-it-through bias that an independent read must check; Glean does **capture**, which is *ungated
  by design* (ADR 0005 — capture is ambient, no filtering, no asking). Importing presort's
  propose-and-wait gate here would reintroduce the very ceremony the capture rule forbids and force
  the human to hand-run N `bd create`s. So the fork files directly and **reports the filed IDs** for
  a cheap eyeball; the "is this worth keeping" decision is deferred to the normal refinement pass,
  source-agnostically (the inbox-flood concern, dotfiles-o1o).
- **A thin main-context wrapper, not a pure `context: fork` skill.** A fork knows nothing of the
  current session's UUID, so `/glean` runs a sliver in the main context to get the UUID (from the
  harness-provided scratchpad path `…/<session-uuid>/scratchpad`), discover that session's transcript
  set by UUID (the main `<uuid>.jsonl` + every `<uuid>/subagents/*.jsonl`, plus `.meta.json`
  sidecars; newest-by-mtime as a fallback only if the UUID is unavailable), then spawns the read-only
  fork with those paths. The fork
  inherits **nothing** otherwise — not history, not skills, and not the injected operating ruleset
  (the `discovery-ruleset` SessionStart hook fires only on `startup|clear|compact`, never for a
  fork). So the SKILL.md is **self-contained**: it carries its own `bd create` filing recipe inline,
  exactly as `presort` restates its `bd` reads.
- **What counts as an Impediment is fixability, not the error flag.** v1 gleans one category, the
  **Impediment** (`umbel/CONTEXT.md`): friction the agent had to route around that *would recur and
  cost tokens again unless an instruction, skill, or tool changed*. A bare `is_error` from normal
  probing (empty `grep`, a guard that fails) is **not** an Impediment; a denied permission, an
  interface retried three times, a misfiring bundled skill, or an ambiguous injected instruction is.
  The highest-value class is friction with *our own* instructions/skills — those we can actually fix.
- **Evidence-rich body, remediation left open.** The fork's unique value is harvesting the
  perishable evidence before the session evaporates: it quotes the friction from the transcript (the
  failing command, the error, the retry count, roughly what it cost) into the bead body. It does
  **not** decide the fix — choosing *which* instruction to change is a design decision with more than
  one defensible answer, i.e. a **grill**, not a capture-time call. Glean produces a well-evidenced
  grill candidate; the "new instruction / skill / change" is decided later in refinement.
- **One extensible command, not a family.** The harvest *mechanism* (fork → read transcript → file
  typed captures) is category-agnostic; only the detection criteria differ. So categories are added
  as a detection rule + a new `type:*` label value, **never** a new command — keeping the "one
  canonical command, not a decision tree" grain. Impediments are the beachhead; the category list is
  open. (Structural precedent: `presort` is already one skill emitting four categories.)
- **One source, both tracks.** A single source dir `umbel/skills/local/glean/` is dual-listed in
  `discovery.md` and `delivery-base.md` (the base layer, beside `grill-with-docs`, because the
  harvest is method-agnostic). This is genuine single-source sharing, not the cross-bundle copy
  duplication ADR 0010 guards against. The skill needs no track conditionals — it discovers
  whatever friction the transcript holds.

**Relationship to `plannotator/compound`.** compound is the repo's *other* compound-engineering
harvester; glean and it are deliberately distinct siblings, not duplicates. compound harvests the
**human's plan-rejection feedback** (Plannotator's denied-plan archive; `ExitPlanMode` denials as a
CC-transcript fallback) across the **whole archive**, longitudinally, and emits an HTML report + an
`EnterPlanMode` improvement hook — it improves *planning*. Its CC parser explicitly *strips* tool-
error noise to keep only human denial reasons, i.e. it discards exactly what glean keeps. glean
harvests the **agent's harness friction** from a **single** session (main + subagents) into
`type:impediment` beads — it improves the *workflow/tooling*. Orthogonal signals, orthogonal
consumers. The kinship is real in one direction: compound's longitudinal *reduce-to-actionable-
instructions* shape (incremental cutoffs, a corrective-instruction inject hook) is precisely the
**Gap B** layer this ADR scopes *out* of glean — so a future cross-session reducer over
`type:impediment` beads should be **modelled on compound, not invented fresh** (dotfiles-8vq).
Factoring a shared transcript-parse core between the two extractors is deferred under ADR 0010's
recurrence gate (n=2 is premature). compound itself is currently vendored-but-dormant (in neither
adopted bundle; `disable-model-invocation: true`).

## Considered options

- **Rely on ambient capture alone** — rejected: ambient capture is a focus failure for the agent's
  own friction (it routes around errors mid-task). Hand-captured impediments exist (dotfiles-iv6,
  -sp0) but are the exception; the systematic misses are the target.
- **A SessionEnd hook spawning headless `claude -p`** (fully automatic) — rejected for v1: it pays a
  full headless-agent cost on *every* session exit (most sessions glean nothing), is the opposite of
  observable, and abandons the in-session fork shape. A SessionEnd/Stop *nudge* to run `/glean`
  remains a cheap, separable later add-on if forgetting proves real. Manual invoke (like `/presort`,
  `/handoff`) suffices: a deliberate end-of-session ritual is reliable in a way in-the-moment capture
  is not.
- **Copy presort's read-only propose-table** — rejected: capture is ungated by design, so a
  capture-time keep/drop gate is the wrong model and reintroduces ceremony. (See Decision.)
- **Run in the main context instead of a fork** — rejected: loses the independence from the main
  agent's self-justifying narrative and pulls large-JSONL parsing into the main context.
- **A family of narrow commands** (`/scan-impediments`, `/scan-techniques`, …) — rejected: the
  mechanism is identical across categories, so siblings proliferate commands (a decision-tree smell)
  where one parameterised harvester with a `type:*` axis is the natural shape.

## Consequences

- New skill `umbel/skills/local/glean/SKILL.md` (thin main-context wrapper + read-only fork,
  self-contained `bd create` recipe); add `local/glean` to `discovery.md` *and* `delivery-base.md`
  skill lists.
- The fork does **not** `Read` raw transcripts (one session dir is ~2 MB across dozens of subagent
  files; `Read` truncates and would burn the fork's context). A shipped extractor
  (`scripts/extract.py`, precedent: `plannotator/compound/scripts/`) streams main + every
  `subagents/*.jsonl` and emits a compact candidate list — flag `tool_result.is_error`, join each to
  its command via `tool_use_id`, detect retries, attribute subagent friction via `.meta.json`. The
  fork judges that distilled list (the fixability test) and files. Deterministic parse in code,
  judgment in the model. Pinned by `writing-skills` TDD: the permission-denial marker and the
  retry-similarity heuristic.
- Every gleaned bead carries a `type:*` label; v1 emits only `type:impediment`. This is a *category*
  axis orthogonal to the `stage:*` *lifecycle* axis, so it does not bloat the triage states
  (`docs/agents/triage-labels.md`). Existing hand-captured impediments may be back-labelled
  opportunistically.
- `umbel/CONTEXT.md` gains the **Impediment** and **Glean** terms.
- Inbox-flood / dedup is explicitly *out of scope* for this skill — it is source-agnostic and handled
  by refinement (dotfiles-o1o).
- Gap B (cross-session recurring-friction → actionable fixes) is *out of scope* here and tracked as
  dotfiles-8vq, to be modelled on `plannotator/compound`'s longitudinal map-reduce + improvement-hook
  pattern, consuming the `type:impediment` beads glean files.
- Tracked as dotfiles-mqq (`stage:ready`). Overlaps dotfiles-iv6 (worktree-teardown impediment, a
  paradigm gleanable case) — that fix is delivery work the gleaned/captured bead feeds, not part of
  building `/glean`.
