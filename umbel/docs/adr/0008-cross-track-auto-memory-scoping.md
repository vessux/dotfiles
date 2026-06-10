---
status: accepted
---

# Cross-track auto-memory: tag by track, treat other tracks as non-authoritative

Auto-memory is keyed by **working directory** (`~/.config/claude-code/projects/<cwd-slug>/memory/`),
so every track sharing a repo — discovery and delivery — reads one pool. Bundles scope
operating-rules/skills/hooks per track, but **not** memory. Worse, the `MEMORY.md` index loads in
**full** every session regardless of track, and recall of individual memory files is
harness-controlled — it matches on `description`, and will **not** filter on any marker we add. The
failure this surfaced: a *delivery*-track session read a *discovery* worklist note ("NEXT: grill the
multi-harness epic") out of the always-loaded index and surfaced it **as a recommendation**.

The first fix (for dotfiles-az7) was a discovery-seed rule: *never put volatile `NEXT:`/worklist
state in always-loaded memory*. It was a symptom-patch — it redirected only volatile next-action,
did nothing for the larger half (durable track-specific facts bleed identically), read as
"no memory in practice", and sat in one seed when the bleed is cross-track.

**Decision.** One soft rule, honoured by both tracks. A memory that belongs to **one** track carries
a **visible textual tag** — a leading `(discovery)` / `(delivery)` in *both* its `MEMORY.md` index
line and the file body. **No tag means global** (cross-cutting facts — shell config, repo topology —
which most memories are; tagging is optional and used only for track-specific entries). Agents read
another track's memories as **context, not authority**: informative awareness, never a directive.
The **backlog stays the authoritative source of work, per track** — discovery's is the open beads
inbox it refines; delivery's is its claimed unit (a ready bead on private, an assigned issue on
public) — so a tagged `NEXT:` *may* live in memory; it is simply non-authoritative.
The rule lives in **both** the `discovery` and `delivery-base` seeds (writer- and reader-side apply
to both tracks).

## Considered options

- **Keep volatile next-action out of memory entirely (the first az7 fix)** — rejected: patched only
  the worklist symptom, left durable track-specific facts bleeding, and read as discouraging memory
  altogether. It was placed in the discovery seed alone, though the reader that gets misled is the
  delivery agent.
- **Structural per-track / per-bundle memory directories** — *parked*, not chosen: auto-memory is
  cwd-keyed, so a real split needs a harness-level key change (a per-bundle `CLAUDE_CONFIG_DIR`
  override, or umbel `isolate: true`). That is unreachable from the seeds, needs verification, and is
  cross-repo (vessux/umbel). Worth revisiting only if soft marking proves insufficient.
- **A `metadata.track` frontmatter field** — rejected: recall ignores unknown frontmatter, so it
  would be decorative. Only the agent reads/writes/manages memory, so the marker belongs exactly
  where the agent reads it — visible text in the index line and body.
- **Visible tag + non-authoritative convention (chosen)** — given the harness won't filter recall and
  `MEMORY.md` always loads in full, agent self-discipline on a visible marker is the *only* lever that
  both keeps memory rich and disambiguates it across tracks.

## Consequences

- The control is **soft** — convention, not an enforced mechanism. Acceptable because agents are the
  sole readers/writers of memory; consistent with ADR-0005/0007's convention-over-machinery stance.
- The marker is **visible text in two places** (the `MEMORY.md` line and the file body) so scope
  travels both with the always-loaded index and with a standalone recall.
- Tagging is **optional**: most memories are global and stay untagged; only one-track entries get a
  tag.
- Both `discovery` and `delivery-base` seeds (each tier) carry the rule; the tier only changes the
  backlog reference (beads vs GitHub Issues), not the marking convention.
- `umbel/CONTEXT.md` gains the **Track** and **Bundle** terms and a "bundle-specific → track-scoped"
  flagged ambiguity.
- **Supersedes** the narrower memory-hygiene rule first shipped for dotfiles-az7.
- Cleaning the one observed violation (tagging the umbel discovery/delivery-workflow memory) is
  tracked as dotfiles-1vv, blocked by az7.

Tracked as dotfiles-az7 (`stage:ready`).
