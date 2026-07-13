---
status: accepted
---

# Delivery-gate: server-side proof classes, acceptance criteria in the definition of ready, and the judgment-loop law

Merge is the gating point of delivery, but on a no-CI repo "green" is vacuous, and client-side
discipline is the compliance-decay class dotfiles-b6r documents (the agent that skips the method
also skips a local gate). We gate merges with a **server-side required check — the
delivery-gate** — that validates proof the *workflow itself* can mandate, method-agnostically
(per ADR 0002 this is a base-contract obligation; no method required). The deepest class fixes
the fully-agentic grading problem: **the implementer must not write its own exam**, so acceptance
criteria are authored at Refinement, before any implementer context exists, and folded into the
definition of `stage:ready`.

## Decision

Four proof classes, with a strict authority split:

- **C1 — protocol proof** (server-checkable): branch matches `delivery/<id>`; the PR links exactly
  one unit and it matches the branch's id; branch current with main. The workflow auditing its own
  invariants — claim-before-work, one unit per PR, traceability.
- **C2 — verification proof** (structure mandatable, truth not): a schema'd verification block in
  the PR body, failing on absence. Truth comes from C3 where a test surface exists; the gap is
  deliberate pressure — a repo's gate gains teeth exactly as fast as its tests do.
- **C3 — executable proof**: run the repo's checks. This repo's first real test surface is the
  epic's own deliverable (clerk's bats suite — printed output tested like exit codes — plus
  shellcheck on `bin/`), so the no-CI floor is genuine CI, not a placeholder.
- **C4 — acceptance proof**: Refinement's output is twofold — the work *and the proof it is done
  as designed*. `clerk inbox ready` refuses units without acceptance criteria (presence is
  structural; quality is grill judgment); `submit` stamps the unit's criteria into the PR body and
  requires one evidence entry per criterion — delivery may add evidence, never narrow; **an
  executable criterion must land as a test, not a transcript** (workflow-level TDD). If delivery
  cannot fulfil the criteria as designed, `backlog return` sends the unit back to discovery with a
  mandatory reason, auto-filed as a capture.

Authority split: the server-side check is authoritative for what the server can see (C1–C3, and
C4's criterion-evidence correspondence, which submit made server-visible); claim-state truth stays
clerk-side (`submit`/`finish` hold `bd` access; an Action cannot read the Dolt store). `clerk
submit` runs the same gate script as a local preflight — fast feedback, never the authority.

**Review-required branch protection is the attended dial** (the merge key, K1 of ADR 0015):
today's posture is review-required + delivery-gate; flipping a repo toward unattended is removing
review-required and leaving the check — a platform setting, not prompt discipline.

**The judgment-loop law**: every judgment point in the workflow declares its compounding loop —
the signals that indict it, the glean category that carries them, and the guidance artifact its
lessons land in. One circuit for all loops: signals are filed ungated (clerk-filed ambient
captures; glean's transcript sweep) → they land in the ordinary inbox → pre-sort clusters them via
`inbox dups` → one grill lands the cluster as a single compounded unit → the deliverable is a
**gated edit to the guidance artifact**. The intent anchor is the human at the attended grill; the
loops compound the *craft* so human attention is spent on rulings, not proof-mechanics.

Loop map at inception:

| Judgment point | Category | Guidance artifact |
|---|---|---|
| Grill criteria authoring | `criteria-miss` (returns; trivially-green criteria; evidence-beyond-criteria) | acceptance playbook (`umbel/docs/acceptance-playbook.md`, lazily created, loaded by grill skills) |
| Pre-sort classification | `sort-miss` (proposal-vs-disposition divergence read from transcripts; empty grills; returned wave-throughs) | presort successor's judgment guidance |
| Pregrill prep | `prep-miss` (never-true premises; agenda gaps; draft criteria rewritten wholesale) | pregrill guidance in the same skill |
| Workflow friction | `impediment` (ADR 0012) | the instruction/skill/tool at fault |

Delivery *build* craft is deliberately uncovered — that is the swappable method's concern;
methods declare their own loops under the law.

**Pregrill** (the prep half of the loop): pre-sort's successor is decision-free with exactly one
write verb — `clerk inbox pregrill <id>` appends a dated, structured, state-neutral note (open
decisions, premises each with a suggested verification, draft criteria) **onto the unit itself**
(a bead exists to hold perishable context). Dispositions stay ephemeral per pass; prep persists.
Pregrill fires per-delta (note missing or stale — body edited after note date, cluster grew),
never per-pass, and never at capture time (prep before classification spends on the doomed).
Pre-sort remains **manually invoked**, like today; the ambient chain (SessionStart: glean →
presort-delta) is designed but shelved as a later dial. The grill's opening move is to re-verify
the pregrill's premises live.

## Considered options

- **Review-only gate** — rejected as the floor: blocks unattended forever; survives as the
  attended dial.
- **Submit-side gate only** — rejected as authority: client-side discipline is b6r's decay class;
  survives as the preflight.
- **Method-compliance check (superpowers artifacts)** — rejected as the base gate: the workflow
  can only honestly mandate proof of its *own* invariants; per-method checks stack on top as
  additional required checks.
- **Pregrill at capture time** — rejected: preps captures that refinement will drop, and smuggles
  the classifier into the prep fork; glean's batch filings would fan out forks blindly.
- **Persisting pre-sort proposals as state** to audit overrides — rejected: proposals stay
  ephemeral by ruling; the session transcript is the audit record and glean is its reader.

## Consequences

- This repo gains CI (the delivery-gate workflow) and branch protection as part of the epic —
  no repo in the workflow stays gate-less.
- `stage:ready` is redefined: no open decision **and** stated acceptance criteria. Pre-sort may
  not propose `ready` for a criteria-less capture (demotes to grill, may draft criteria as a
  proposal).
- The squash commit carries the criteria-evidence summary, so `git log` is the audit surface the
  `criteria-miss` glean reads.
- Glean's category list grows to four; `/glean`'s harvest mechanism is unchanged (ADR 0012,
  mechanics now `clerk glean` per ADR 0015).

## Amendment (2026-07-09): submit / delivery-gate operational contracts (dotfiles-dft.4)

`clerk backlog submit` and the delivery-gate use one gate implementation, exposed as the first-class
verb `clerk backlog gate`. `submit` invokes it locally as a preflight; the GitHub Actions required
check invokes the same verb in CI. A gate run exits `0` only when every proof class passes and exits
`6` when one or more proof classes fail. Gate failures report every failing class in one run, not
only the first failure.

The gate has two input modes. Local preflight receives the branch being submitted and a PR body file
because the PR does not exist yet. CI derives the branch/base context from `GITHUB_*` and reads the
PR body through `gh pr view`. The CI gate is authoritative; submit's local preflight is fast
feedback.

The PR body schema is:

```md
## Verification

Unit: dotfiles-<short>

Checks:
- bats: <summary>
- shellcheck: <summary>

## Acceptance criteria
- <criterion 1, verbatim from the unit>
  evidence: <test name / probe / transcript ref>
- <criterion 2, verbatim>
  evidence: <...>
```

C2 requires `## Verification`, `Unit:`, and `Checks:` to be present. C4 requires each stamped
acceptance-criteria bullet to be immediately followed by an indented `evidence:` line. Delivery may
add criteria bullets but may not remove or narrow the stamped criteria; executable criteria must cite
executable evidence.

C1 linkage is backend-specific. For the current beads-backed backlog, the body must contain exactly
one `Unit: dotfiles-<short>` line, and `<short>` must match the `delivery/<short>` branch token. For
a future GitHub-issues backlog, `closingIssuesReferences` supplies the same exactly-one linked-unit
check. Zero linked units, multiple linked units, or a linked unit that does not match the branch are
gate failures.

Branch currency is part of C1: the delivery branch must strictly contain the fetched base tip
(`merge-base(HEAD, base) == base-tip`). A stale branch fails with a prescriptive rebase message.
This mirrors GitHub's up-to-date protection while making local preflight and CI enforce the same
contract.

On green preflight, `submit` creates the PR with title `<summary> (dotfiles-<short>)` and the body
file above. It **never arms PR auto-merge** in this generation. Review-required branch protection is
the attended merge dial; unattended auto-merge may be introduced only by a later ratified change once
the gate has operated successfully in practice.

This repo's C3 scope for dotfiles-dft.4 is `bats tests/clerk` plus `shellcheck bin/`. The gate must
have parity tests proving the same fixture receives the same per-class verdict through both the local
preflight input mode and the CI input mode.

## Amendment (2026-07-10): solo merge posture for this repo

For `vessux/dotfiles`, the live K1 merge posture is **solo mode**: branch protection requires the
`delivery-gate` check and strict/up-to-date branches, but does not require approving PR reviews.
This keeps ordinary PR merges usable in a solo repository without turning every delivery into an
admin-bypass event.

Solo mode changes the platform dial only; it does not weaken the delivery-gate proof classes. A PR
still cannot merge normally without the required `delivery-gate` check passing, and `submit` still
never arms PR auto-merge. Human attendance is the manual PR merge action after reading the PR body
and gate result, not a GitHub review record. If a real second reviewer becomes available, the repo
may flip K1 back to review-required branch protection without changing the clerk contract.

## Amendment (2026-07-13): returned-branch disposition is a fail-closed grill decision (dotfiles-5jw)

`return` preserves the failed attempt as `returned/<short>` (the criteria-miss loop's raw
material), but no later verb collected it: `claim` bases a fresh `delivery/<short>` on main, and
`inbox ready` / `inbox drop` touched no returned branch. A re-readied or dropped unit could
therefore orphan `returned/<short>` silently.

The grill — already the named consumer of `returned/*` — now supplies an explicit disposition at
its exit points. `clerk inbox ready` and `clerk inbox drop` accept `--returned keep|discard` and
refuse (exit 2) when `returned/<short>` exists and no disposition is given. `keep` leaves the
branch untouched as evidence. `discard` deletes `returned/<short>` locally and from origin; if
origin is unreachable, Clerk deletes the local ref, prints a deferred-to-sync warning, and proceeds
with the ready/drop decision. This makes branch collection a fail-closed judgment, not a hidden
side effect.

Reviving the attempt by renaming `returned/<short>` back to `delivery/<short>` is rejected: the
canonical work branch is the claim lock (ADR 0011), so recreating it outside `claim` forges the
lock, and the rename destroys the evidence ref that the impediment capture cites. Reusing a
returned attempt as a re-delivery base is therefore a claim-side option (`claim --from-returned`,
dotfiles-uky), not a returned-branch rename.
