---
status: accepted
---

# Cross-bundle hook duplication: one source, generated copies — artifacts stay self-contained

Near-identical hook sidecars across bundles (the discovery/delivery ruleset injects are
50 of 51 lines identical, differing only in `TRACK=`) are kept as self-contained per-leaf
copies, but **generated from one in-repo source** so they can't silently drift. Sharing
the code at the umbel layer is rejected; DRY-by-reference is reserved for setup docs.

## Context

`discovery-ruleset/inject` and `delivery-base-ruleset/inject` are identical except line 8
(`TRACK="discovery"` vs `"delivery"`); the `emit()` JSON helper is a third copy in
`delivery-superpowers-locations/inject`. The cost surfaced concretely: a routing/done-condition
fix in discovery's inject (dotfiles-mt1) had to be re-applied by hand to delivery's copy
(dotfiles-izy) because the second copy was **invisible at edit time** — silent drift, not mere
duplication.

umbel is our own tool, so DRY-at-the-umbel-layer (build-time templating, a shared-sidecar
include, or per-bundle artifact parameterization) is genuinely available. But every such path
makes the committed artifact **inert without umbel's build**: today each inject is plain bash
that runs standalone (verified: it reads the committed `.repo-visibility` marker and emits hook
JSON under bare `bash`, no umbel present). umbel copies each referenced leaf dir verbatim
(`bundles-spec`: "copies the entire artifact directory"); a sidecar must live inside its leaf,
and the three injects live in three independently-built bundles. So restatement is **forced at
the artifact boundary** — the question is only how to stop it drifting silently.

## Decision

Draw one boundary across both artifact classes:

- **Runtime artifacts** (hook sidecars + injected seed text) are **self-contained per leaf**.
  They must run standalone (no umbel build-dependency) and injected text must cite nothing
  repo-local (dotfiles-j8x); umbel copies leaves verbatim. Duplication across bundles is
  therefore accepted — but the copies are **generated from one in-repo source**
  (`_ruleset-inject.template` + `gen-ruleset-inject.sh`), so a single edit regenerates every
  copy and the dual-edit failure mode is removed *by construction*. Each generated file carries
  a `# GENERATED from … — do not edit` header pointing back to the source; `gen --check`
  re-derives and diffs for an agent (or future CI) to run. What ships stays fully-resolved,
  standalone bash.
- **Setup docs** (bundle playbooks) are **DRY-by-reference**: `delivery-base.md` defers to
  `discovery.md` ("Same tier setup as discovery", "beads wired by discovery's Wire beads step").
  This is correct, not over-coupling — delivery consumes the ready backlog discovery produces,
  so it structurally presupposes discovery's setup, and the `.repo-visibility` marker is a shared
  substrate (CONTEXT.md). Prose read at setup time has no runtime or portability constraint.

## Considered options

- **DRY at the umbel layer** (parameterized/shared artifacts: `{{TRACK}}` substitution, a
  shared-sidecar include, or per-bundle env injection) — rejected *now*: each breaks the
  artifact's standalone-runnability and pushes correctness into umbel's build, the same
  anti-pattern as a non-self-contained seed (ADR 0002) one level down. It is also speculative
  generality at n=2 hooks in one consumer repo. Parked behind a recurrence gate as a separate
  umbel-side idea — earned only when many bundles across repos are hand-synced.
- **Accept duplication + a "KEEP IN SYNC" banner and/or a manual test** — rejected: the banner
  is unenforceable and a standalone test nothing auto-runs; neither removes the dual-edit failure
  that actually bit (mt1→izy). Codegen collapses the two edit sites into one.
- **Enforce via a git pre-commit hook** — rejected: `.git/hooks/` is uncommitted (dies on clone /
  other machines), and git's single `core.hooksPath` is contended by beads (see dotfiles-8uv).
  Coupling a small DRY fix to that infra question inflates scope. In an agent-operated repo the
  generated-file header enforces "don't hand-edit outputs" at the moment that matters.
- **Do nothing** — rejected: silent drift recurs.

## Consequences

- The two ruleset injects become generated outputs of `_ruleset-inject.template` (kept outside
  any leaf dir so umbel never ships it); edit the template, regenerate, commit both. A `--check`
  mode exists but nothing is depended on to auto-run it.
- The `emit()` triplication is left as-is — a 6-line serialization helper in a genuinely
  different hook that fails *loudly* (malformed JSON) if it drifts; an optional `--check`
  assertion may cover it, but it is not codegen'd.
- `delivery-base.md` keeps deferring to `discovery.md`; no decoupling.
- Generalizes: future near-identical hook sidecars across bundles are generated from one source,
  never shared at the umbel layer — unless the recurrence gate flips and umbel earns a
  first-class shared-artifact capability (its own ADR).
</content>
</invoke>
