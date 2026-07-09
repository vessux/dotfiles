# HANDOVER — clerk epic dft.4 (submit + delivery-gate)

**Status:** Phase 0 (contract grill) in progress. Contracts DRAFTED below, **not yet
ratified by the operator, not yet written to any ADR.** No code written. dft.4 not claimed.
Disposable file — delete once folded into the ADR.

Repo: `/home/kovis/dotfiles` (vessux/dotfiles, PUBLIC, default branch `main`). Issue
tracker = beads (`bd`), NOT GitHub. `bd show dft.4`, `bd show dft` (epic; read its NOTES —
the full ruling trail lives there).

---

## Where we are

The task: deliver **dotfiles-dft.4** — `clerk backlog submit` + the **delivery-gate**
(one gate run both as submit's local preflight and as a GitHub Actions required check),
plus branch protection on this repo. Depends on dft.3 (done); blocks dft.5 (finish
reconciler). Design authority: **ADR 0016** (`umbel/docs/adr/0016-…md`), epic notes
rulings 6/9/17 (+ 5, 11, 13, 15, 16).

Before building, we ran **Phase 0**: a discovery grill to pin the load-bearing contracts
dft.4's acceptance criteria leave underspecified — so delivery does NOT author its own exam
(the C4 anti-pattern the operator flagged hard on dft.3; see bead `dotfiles-4j1` and memory
`escalate-delivery-authored-criteria`). The resolved contracts must land as a **dated
amendment to ADR 0016**, then delivery builds against ratified text.

Premises were re-verified live (this is real):
- Commit convention: `<summary> (dotfiles-<short>)`, id in the subject. The squash message
  IS glean's audit surface (ruling 11) → the PR body must double as that record.
- The `Claude-Session` trailer was dropped (commit 9ad4a3b) — do NOT reintroduce a trailer.
- `bin/clerk:has_acceptance_criteria_section()` already detects
  `^#{1,6}\s*acceptance criteria` or a bare `acceptance criteria:` line; bd emits criteria
  as `- ` bullets. Submit + gate must REUSE this, not invent a parser.
- All five `bin/` scripts are shellcheck-clean (`-S error`) → C3 can cover full `bin/`.
- `gh pr view` exposes `closingIssuesReferences` → gh-backend linkage mechanism is sound.
- Exit-code taxonomy today: `0` ok / `1` doctor-found-problems / `2` usage|unknown /
  `3` not-implemented / `4` marker-unresolvable / `5` claim-conflict.

## Operator decision LOCKED

Branch-protection handling = **in-band via an elevated PAT**. Operator will add
**Administration: write** to the fine-grained PAT for vessux/dotfiles. Then clerk configures
protection itself, submit's auto-merge-arm reads live gate posture, and the
"merge-without-review-impossible" criterion probes for real. Protection is enabled with
**admin-bypass left ON** so the operator's own `git push origin main` finishes still land.

**BLOCKER — not yet done:** `gh api repos/{owner}/{repo}/branches/main/protection`
still returns **403** (PAT not yet elevated, re-verified this session). Until it's elevated,
all branch-protection config + the live probe stay HERMETICALLY STUBBED in the build
(fake `gh` on PATH). The live config + real probe is the FINAL step of dft.4, after the PAT
lands. Re-check with the `gh api …/protection` call — 200 means it's ready.

---

## Phase 0 output — proposed ADR 0016 amendment (AWAITING GRILL/RATIFICATION)

Authority split (drives everything): submit (client, holds bd) STAMPS criteria verbatim into
the PR body; the gate (server + preflight, no bd access) validates only body-internal /
branch-visible facts. This makes C4 server-visible without the Action reading Dolt.

**G1 — gate is a clerk verb `clerk backlog gate`.** One code path, two callers ("one script
shared verbatim" with no separate file). First-class + `--explain`'d. Inputs: branch ref +
body source — locally submit passes the branch-to-push + `--body-file` (**PR doesn't exist
yet at preflight**); in CI clerk reads ref+body from `GITHUB_*` + `gh pr view`. Exit `0`=all
pass, **`6`=≥1 class failed** (new taxonomy member). CI required check = "gate exit 0".
Reports EVERY failing class, never first-fail-only.

**G2 — PR-body schema (C2 presence + C4 correspondence), reusing the criteria detector:**
```
## Verification

Unit: dotfiles-<short>

Checks:
- bats: <summary>
- shellcheck: <summary>

## Acceptance criteria
- <criterion 1, verbatim from the bead>
  evidence: <test name / probe / transcript ref>
- <criterion 2, verbatim>
  evidence: <...>
```
- C2: `## Verification` + `Unit:` + `Checks:` present, else red. Presence only — truth is C3.
- C4: every `- ` criterion bullet immediately followed by `^\s+evidence:\S`; any without →
  red naming it. Delivery may ADD bullets, never remove; executable criterion's `evidence:`
  points at its test.

**G3 — "links exactly one unit" (C1), per backend.**
- bd (this repo): exactly one `Unit: dotfiles-<short>` line; `<short>` == branch
  `delivery/<short>` token. Zero → red "no linked unit"; two+ → red "two linked units".
- gh (future): `closingIssuesReferences` has exactly one == branch token. Same red conditions.

**G4 — branch currency (C1).** Strict-ancestor: `merge-base(HEAD, base) == base-tip`
(base = `origin/main` locally / `GITHUB_BASE_REF` in CI, fetched). Behind → red, prescribe
`git rebase origin/main`. Ahead = the work. Mirrors GitHub "require branches up to date".

**G5 — submit exit codes + auto-merge arm.** Exit `2` = usage (no `--body-file`; not inside a
claimed `delivery/<short>` worktree; bead has no criteria). Exit `6` = preflight gate failed
(stderr names each failing class). On green: create PR with
`--title="<summary> (dotfiles-<short>)"` + `--body-file`=the G2 body; then read live posture
via `gh api …/branches/main/protection` and **arm `gh pr merge --auto --squash` ONLY where
review is NOT required** (unattended); under review-required (this repo, K1) print
"awaiting review", arm nothing. Armed branch unit-tested with stubbed gh; live repo exercises
the not-armed branch.

**C3 scope:** `bats tests/clerk` + `shellcheck bin/` (all clean now). **Parity (criterion 2):**
one fixture driven through gate-as-preflight AND gate-as-CI-entrypoint, assert identical
per-class verdict.

### 5 judgment calls the operator must grill (I chose; they may override)
1. New exit `6` vs fold gate-fail into `2`. (Chose 6 so dft.5 reconciler can branch on it.)
2. Gate as roster verb `clerk backlog gate` vs hidden `clerk _gate`. (Chose roster + explain.)
3. C2 and C4 in ONE `## Verification` section vs two sections. (Chose one.)
4. Strict-ancestor currency vs delegate to GitHub "require up to date" only. (Chose gate-checks.)
5. `evidence:` line format (indented under each bullet). (Chose 2-space indent.)

### Genuinely EXTENDS ADR 0016 (needs blessing, not just consistency)
- New exit code `6`.
- submit's posture-detecting auto-merge arm (reads branch protection → the PAT dependency).

---

## Next steps (in order)

1. **Finish the grill.** Present G1–G5 to the operator, resolve the 5 judgment calls + the
   2 extensions. Expect pushback (memory: they grill before implementing).
2. **Write the amendment** into `umbel/docs/adr/0016-delivery-gate-…md` as a dated
   `## Amendment (2026-07-…): submit / delivery-gate operational contracts (dft.4)` section
   (matches how the epic already appended "ADR 0015/0017 amended" notes). ADR edits land in
   the **main working tree** (discovery track), uncommitted, per house pattern.
3. **Deliver dft.4** via the cc-workflow harness (see below).
4. **Final live step** (after PAT elevated): configure branch protection (delivery-gate
   required + review-required, admin-bypass ON), open a fixture PR so the check runs once and
   gets a name, THEN mark it required. Sequencing quirk: a workflow must run once on a PR
   before it can be marked a required check.

## Delivery approach + findings to apply (do NOT relearn these)

Harness template: the dft.3 workflow script at
`claude-code/projects/-home-kovis-dotfiles/43b1edef-…/workflows/scripts/deliver-dft3-clerk-claim-wf_1f70025c-6a7.js`
— reuse its shape verbatim (PREAMBLE worktree hard-rules + scratch-fixture ban on touching
real repo/beads/origin; CONTRACT block; per-criterion adversarial verifiers; opus lenses;
fix loop; finalize-commit-no-push).

- **Model-tier policy (epic-ratified for .2–.8):** opus orchestrate / **sonnet-xhigh** dev
  (implement+fix, opus on fix round 2) / **haiku** per-criterion verify / **opus** review
  (load-bearing, NON-optional — haiku review returned zero findings where opus found 2 majors).
- **Isolate:** `clerk backlog claim dft.4` provisions `.worktrees/dft.4`; `EnterWorktree` it.
  Every Read/Edit/Write MUST use a path under the worktree — a `/home/kovis/dotfiles/…` path
  silently edits the shared checkout (memory `delivery-worktree-edit-paths`).
- **Split Implement** (memory `delivery-split-implement-phase`): (a) gate verb + its hermetic
  bats, (b) submit + PR-body stamping + its bats (pipeline b after a — submit calls gate),
  (c) thin workflow YAML + CI deps. NOT one monolithic implementer.
- **Verify:** haiku adversarial per acceptance criterion + opus divergence/failpath lenses
  that EXECUTE against scratch fixtures (fake `gh` returning canned PR JSON, scratch git+bd).
  The pivotal test = criterion 2 (preflight vs CI parity on one fixture).
- **Re-verify fixed review findings**, not just failed criteria (memory
  `delivery-reverify-review-fixes` — dft.2 shipped a half-applied fix from skipping this).
- **Trust the ratified DESIGN**, execute the edit/WHERE list, verify your OWN work — don't
  re-run discovery's premise checks (memory `delivery-trust-resolved-design`).
- **Finish:** dft.4 is NOT dogfooded through its own gate (that's dft.8). It lands the old
  way: local ff-merge → **operator pushes main** (memory `delivery-finish-user-pushes-main`;
  the harness classifier blocks agent pushes to main) → `ExitWorktree(remove,
  discard_changes:true)` after confirming the commit is on main (memory
  `delivery-finish-worktree-discard`) → check the shared checkout isn't dirty with a
  concurrent session's work before ff (memory `delivery-finish-dirty-shared-checkout`) →
  `bd close` + synchronous `bd dolt push` only AFTER the operator confirms the push landed.

## Build facts

- `bin/clerk` (~1600 lines): top-level dispatch in `main()` (~line 1477); `not_implemented()`
  = exit 3 stub for unbuilt verbs; `backlog` roster already includes `submit`/`finish` arms
  routed to the stub + truthful `--explain` arms (lines ~257–280) — REPLACE the stub arms,
  add `cmd_backlog_submit` + `cmd_backlog_gate` + dispatch, keep `--explain` truthful.
- Reuse helpers: `marker_gate`, `repo_root`, `read_marker`, `has_acceptance_criteria_section`,
  the color/ANSI helpers (16-color only, TTY/NO_COLOR/CLICOLOR_FORCE gated), `usage_error`.
- Output discipline: every refusal PRESCRIBES the next action + names the resolved path;
  printed output is load-bearing, asserted VERBATIM in bats. No user-facing string may name
  `bd`/`beads` (epic ruling 2 opacity ban; `--explain` is exempt).
- Tests: `tests/clerk/*.bats` + `tests/clerk/helpers.bash` (call `git_sandbox` first in every
  `setup()` — redirects GIT_CONFIG_GLOBAL/SYSTEM into the tmpdir; a dft.3 leak wrote
  `init.defaultBranch` into the real global config). Suite uses real `bd` on scratch dbs,
  stubbed `gh`, scratch bare-git origins.
- **CI deps for the delivery-gate workflow (`.github/workflows/delivery-gate.yml` — repo's
  FIRST workflow):** install **bd (beads, pin a version), bats, shellcheck, jq**; `gh` +
  `GITHUB_TOKEN` are runner-provided. Trigger: `pull_request`. It runs `bin/clerk backlog
  gate` (which self-detects CI context).

## Reference
- ADR 0016 (proof classes C1–C4, authority split, judgment-loop law).
- ADR 0015 (clerk facade, one binary, exit taxonomy, opacity), ADR 0017 (tier retired,
  `.clerk` marker, merge-gate read-live-not-stored).
- Epic `bd show dft` NOTES: rulings 5 (two verbs), 6 (delivery-gate), 11 (SQUASH, id in
  subject, no-ancestry merged-detection), 13 (tier retired), 15 (run-context matrix),
  16 (three-keys K1 review-required = merge key), + MODEL-TIER POLICY.
- Memory dir `~/.config/claude-code/projects/-home-kovis-dotfiles/memory/`: the `delivery-*`
  files + `escalate-delivery-authored-criteria` + `verify-premise-before-recommending` +
  `agent-operated-no-by-hand`.
- Bead `dotfiles-4j1` = the dft.3 criteria-miss precedent (ratified-contracts pattern).

