---
status: accepted
---

# Private tier records decisions as ADRs + CONTEXT.md (drop worklog.jsonl)

ADR 0001 gave private repos a committed `worklog.jsonl` (a terse, append-only decision journal) while
public repos used ADRs, on the logic that a solo private repo has no other authors to reinforce an
industry standard against. In practice the worklog bought little over the artifacts the discovery
sharpening skills (`grill-with-docs`, `improve-codebase-architecture`) *already* produce — **ADRs**
under `docs/adr/` and a root **`CONTEXT.md`** glossary — and it split the two tiers' decision record
needlessly.

**Decision.** Both tiers record decisions the same way: **ADRs + `CONTEXT.md`**, created *lazily* (only
when there's a decision or a term worth recording). The private tier drops `worklog.jsonl`. The only
thing that now differs by tier is the **backlog** (GitHub Issues on public, beads on private). This
supersedes ADR 0001's private-tier worklog decision and its "worklog kept private on public repos"
rejected-option reasoning.

## Consequences

- `seed.private.md`, both `inject` marker-absent recipes, and `bundles/discovery.md` are updated; ADR
  0001 is annotated as superseded-in-part.
- A repo migrating from an old `worklog.jsonl` distils it into ADRs regardless of tier (rather than
  freezing it on private).
- On a *public* GitHub repo running the private (light) tier — e.g. a public dotfiles repo — the
  ADRs and `CONTEXT.md` are public. That's fine for non-sensitive config rationale, and matches the
  fact that the beads inbox is already public there.
