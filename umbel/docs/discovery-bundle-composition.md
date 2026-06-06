# discovery bundle — composition decisions (round 2)

Round 1 annotations folded in. Top section = **settled** (FYI, no action). Middle =
**still open** — annotate these. Bottom = the **full origin inventory** you asked for.

---

## ✅ Settled in round 1

**Skills:**
- **IN (discovery):** `triage`, `to-prd`, `grill-me`, `grill-with-docs`, `zoom-out`,
  `prototype`, `improve-codebase-architecture` (confirmed: it only *proposes*, so it's a
  backlog source → discovery), `annotate` + `last` (your "easy feedback on md/long convos"),
  `handoff` (handoff between discovery sessions).
- **OUT:** `setup-goal` (dropped), `visual-explainer` (dropped), `writing-plans` (stays
  delivery), `tdd` (delivery owns via superpowers).
- `to-prd` ≠ `to-issues`: `to-prd` = one idea → a PRD spec, published + `ready-for-agent`.
  `to-issues` = a plan/PRD → many vertical-slice tickets. Different scales. (`to-issues`
  fate is open below.)

**Agents:** author a **`presort`** agent (reads open beads, proposes
dup-merges + priority/type; keep/drop/promote stays yours). ✓ *(named `triage-presort`
at first; renamed to `presort` when "triage" was purged — see ADR 0003.)*

**MCPs:** ship **`local/tuidriver`** only. No beads/GitHub MCP (CLI + `gh` is enough). ✓

**Settings:** **none.** You run sandbox automode, so no `bd` permissions allowlist needed,
and nothing else earns a setting. ✓

**Hooks:** sync is **beads' own job** — `bd hooks install` wires
post-merge/pre-push/post-checkout + Dolt remotes + auto-export. So any discovery
session-start hook would *not* sync. That collapses the hook question (see D-HK below).

**Playbook (settled):**
- D-15 ✓ reword the fork to "is the GitHub repo public or private?" (decide via
  `gh repo view`, no judgment call).
- D-16 ✓ rewrite the sync paragraph to beads' real ref-based config — *after* a hands-on
  first-setup check confirms the exact keys (won't fabricate them).
- D-17 ✓ borklog→beads migration: left to the applying agent, no dedicated subsection.
- D-18 ✓ openlock reshape: out of scope for the bundle, handled as a one-off.

---

## 🔲 Still open — annotate these

### O-1 · A separate `setup` bundle? (raised on S4 + write-a-skill)

You flagged that `setup-matt-pocock-skills` is one-time setup, not steady-state discovery —
*"maybe we need some kind of setup bundle first?"* The setup-flavored things in the library:
`setup-matt-pocock-skills` (tracker vocab), `write-a-skill` (authoring), plus the bundle's
"Applying" playbook, beads init, hook install, and the CLAUDE.local.md seeding (O-6).

Tension: `to-prd`/`to-issues`/`triage` all say *"run `/setup-matt-pocock-skills` if the
tracker vocab isn't provided"* — so it's a **dependency** of the core discovery skills. A
separate setup bundle splits a dependency away from its dependents.

- (a) **Keep `setup-matt-pocock-skills` in discovery** (it's a dependency); the playbook
  just notes it's run once at setup. No setup bundle. ← **my pick**
- (b) **Author a `setup` bundle** (setup-matt-pocock-skills + write-a-skill + the
  onboarding playbook) that you load once per repo, then switch to discovery.
- (c) Setup isn't a bundle — it's purely the bundle.md "Applying" playbook prose.

### O-2 · A small `base` bundle both tracks extend? (raised on handoff)

`handoff` (and `caveman`, arguably `karpathy-guidelines`) are **mode-agnostic** — useful in
both discovery and delivery. Right now there's no shared base, so cross-cutting skills get
duplicated into each track's list.

- (a) **Author a `base` bundle** (`handoff`, `caveman`, …) that *both* discovery and
  delivery `extend`. DRY; one home for cross-cutting skills. ← **my pick**
- (b) **No base** — just list `handoff` in each track that wants it. Simpler, some dupes.

### O-3 · `brainstorming` — keep or drop? (you: "fighting same space as grill-with-docs")

The distinction: `brainstorming` is **divergent** (generate/explore options on a fuzzy
idea); `grill-me`/`grill-with-docs` are **convergent** (stress-test an existing design,
find holes). Real difference — but you flagged the overlap, and you already cut `setup-goal`
(the other interview-y refiner).

- (a) **Drop `brainstorming`** — grill-* + your own thinking cover idea refinement. ← **my
  pick** (matches your instinct to thin out overlapping refiners).
- (b) **Keep it** — divergent ideation is genuinely upstream of stress-testing.

### O-4 · `to-issues` — keep (optional) or drop?

It's the only tool that produces vertical-slice tickets, and that work *must* live in
discovery (delivery never creates backlog items). But it only matters when a PRD is big
enough to shard into an epic; most beads promote via `to-prd` alone.

- (a) **Keep it** — available for the epic-sharding case, playbook marks it optional. ←
  **my pick** (preserves the "delivery doesn't own the backlog" line).
- (b) **Drop it** — `to-prd` is enough; epic-sharding is rare and can be done ad hoc.

### O-5 · `diagnose` — discovery or delivery? (you: "helpful when investigating bugs")

`diagnose` is a *full* loop (reproduce → minimise → hypothesise → instrument → fix →
regression-test) — that's execution = delivery. During **triage** you sometimes need a
*light* "is this bug real / how bad?" read, which `zoom-out` + reading code already cover.

- (a) **Delivery only** — keep the full debug loop on the build side; triage uses
  zoom-out. ← **my pick**
- (b) **Both** — also expose `diagnose` in discovery for triage-time bug investigation
  (accepts some track blur).

### O-6 · Where do the workflow rules live on a PUBLIC repo? (your free-text)

The playbook says *"CLAUDE.md carries the operating ruleset."* But on a public repo the
beads/triage/worklog workflow is a **private idiom** contributors don't run — committing it
to `CLAUDE.md` pollutes the public face (the very thing ADR-0001's public=curated principle
avoids). Logged as umbel feature `bk-2026-05-31T19:33:12Z` (seed a gitignored
`CLAUDE.local.md`). The *design* call here:

- (a) **Public-tier rules → gitignored `CLAUDE.local.md`; committed `CLAUDE.md` stays
  public/contributor-facing.** Private-tier rules → committed `CLAUDE.md` (fine, repo is
  private). Pending the umbel seeding feature to automate it. ← **my pick**
- (b) Keep all rules in committed `CLAUDE.md` regardless of tier (accept the public leak).

> **SUPERSEDED (2026-06-01).** Neither (a) nor (b). The operating ruleset is no longer
> filed in *any* repo file — it is **injected** each session by a per-bundle SessionStart
> hook reading a committed `.repo-visibility` marker (`public`|`private`) → `seed.<tier>.md`.
> No `CLAUDE.local.md`, no `.gitignore` edits, no umbel feature; committed `CLAUDE.md` stays
> the public face. See umbel `docs/worklog.jsonl` @ 2026-06-01T09:29:20Z; backlog
> `bk-2026-05-31T19:33:12Z` resolved. This collapses O-6.

### D-HK · Discovery session-start hook (revised — sync removed)

Since beads owns sync, the only remaining value is a **report-only nudge**.

- (a) **No custom hook** — CLAUDE.md + beads' own hooks are enough. ← **my revised pick**
  (the nudge is marginal once sync is off the table).
- (b) **Minimal report-only hook** — print `bd count --status=open` + "run a triage pass?"
  at session start.

---

## 📋 Full origin inventory (every library skill → disposition)

| Skill | Source | Disposition |
|-------|--------|-------------|
| triage | pocock | **discovery** |
| to-prd | pocock | **discovery** |
| to-issues | pocock | **discovery?** (O-4) |
| grill-me | pocock | **discovery** |
| grill-with-docs | pocock | **discovery** (+ delivery for ADR writing) |
| zoom-out | pocock | **discovery** |
| prototype | pocock | **discovery** |
| improve-codebase-architecture | pocock | **discovery** (proposes only) |
| annotate | plannotator | **discovery** |
| last | plannotator | **discovery** |
| handoff | pocock | **discovery** (→ base? O-2) |
| setup-matt-pocock-skills | pocock | **discovery / setup?** (O-1) |
| brainstorming | superpowers | **discovery?** (O-3) |
| diagnose | pocock | **delivery?** (O-5) |
| caveman | pocock | base / cross-cut (O-2) |
| write-a-skill | pocock | setup / authoring (O-1) |
| writing-plans | superpowers | delivery |
| tdd | pocock | delivery (dup of superpowers TDD) |
| test-driven-development | superpowers | delivery |
| systematic-debugging | superpowers | delivery |
| executing-plans | superpowers | delivery |
| finishing-a-development-branch | superpowers | delivery |
| requesting-code-review | superpowers | delivery |
| receiving-code-review | superpowers | delivery |
| subagent-driven-development | superpowers | delivery |
| dispatching-parallel-agents | superpowers | delivery |
| using-git-worktrees | superpowers | delivery |
| verification-before-completion | superpowers | delivery |
| using-superpowers | superpowers | delivery (superpowers meta-announce) |
| writing-skills | superpowers | setup / authoring |
| review | plannotator | delivery (code-review UI) |
| compound | plannotator | neither (plan-archive retro/analytics) |
| visual-explainer | plannotator | dropped |
| setup-goal | plannotator | dropped |
| revdiff | umputun | delivery (diff review) |
| karpathy-guidelines | local | base / delivery (coding guidelines) |
| borklog | local | **legacy** — the convention this workflow replaces |

---

## Free-text

Anything else this round missed?
