---
name: discovery-ruleset
description: Inject the discovery operating ruleset at session start, tier-selected from the committed repo-root .repo-visibility marker.
event: SessionStart
matcher: "startup|clear|compact"
command: ./inject
async: false
---

SessionStart hook for the `discovery` bundle. Reads the committed repo-root
`.repo-visibility` marker (`public` | `private`) via `git rev-parse --show-toplevel`
and injects the matching `seed.<tier>.md` as `additionalContext` — the standing
operating procedure for the discovery track on this repo.

- Offline-safe: the marker is read from disk, never the network, so sandbox /
  no-`gh` sessions resolve it.
- Matcher `startup|clear|compact` (mirrors superpowers; omits `resume`, which
  retains the original injection): re-asserts the rules after a compaction, the
  way project-root `CLAUDE.md` is re-read.
- Marker absent/unreadable → injects a self-contained "create `.repo-visibility`"
  prompt instead of guessing the tier.

The two `seed.*.md` sidecars are each a complete, self-contained procedure (no
shared `common` file): a single coherent ruleset is followed; a concatenated
common+delta reads as optional context and drifts.
