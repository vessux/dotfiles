# discovery / delivery — handover & next steps

Snapshot for a clean session. Auto-memory (`project_discovery_delivery_workflow`) is the
short bridge; this is the depth.

## Where we are

The **discovery** bundle is fully designed, written, and compiles:

- `~/.config/umbel/bundles/discovery.md` — frontmatter (12 cherry-picked skills across
  pocock + plannotator, `local/triage-presort` agent, `local/tuidriver` MCP; **no**
  `extends`) + rewritten playbook body.
- `~/.config/umbel/agents/local/triage-presort/AGENT.md` — read-only inbox pre-sort agent.
- Validated: `umbel build discovery` → `discovery-f86cbf2d9656`, all artifacts resolve.

Decision trail (2-round Plannotator grill, every rejected option):
`~/.config/umbel/docs/discovery-bundle-composition.md`.
High-level workflow ADR: `~/.config/umbel/docs/adr/0001-discovery-delivery-workflow.md`.

## Next, in order

1. ✅ **DONE — operating-ruleset delivery** (was: "umbel `CLAUDE.local.md` seeding
   feature"). Resolved by REVERSAL: **no umbel feature.** The ruleset is **injected** each
   session by a per-bundle SessionStart hook (`local/{discovery,delivery}-ruleset`) that
   reads a committed repo-root `.repo-visibility` marker (`public`|`private`) and injects
   the matching `seed.<tier>.md` — nothing seeded into the repo, no `.gitignore` edits,
   umbel untouched. `-p` injection probed; both tiers + absent-marker fallback
   live-verified. Decision + rejected alternatives: umbel `docs/worklog.jsonl` @
   2026-06-01T09:29:20Z; backlog `bk-2026-05-31T19:33:12Z` deleted. Marker is **committed**
   (travels into sandboxes) and carries no `umbel` in its name (workflow's fact, not the
   tool's).

2. ✅ **DONE — delivery split into base + swappable method** (replaced the old
   `extends: [superpowers, plannotator]` monolith). Two layers:
   - **`delivery-base`** — the *invariant contract*, tier-aware via its own inject hook
     (`local/delivery-base-ruleset`): scope-in → claim → **capture-and-escalate, never
     decide inline** → done (+ public review gate). Plus the *shared delivery tooling*:
     `plannotator/annotate`+`last`, `pocock/grill-with-docs`, `local/tuidriver` MCP. Not
     run alone.
   - **`delivery-superpowers`** — the first *method*: `extends: [delivery-base,
     superpowers]`, **no custom hook** (superpowers' own announce-hook + skills carry
     prep+execution). Injection = two coherent blocks (contract + method).
   Future methods swap by extending `delivery-base` and adding only their own procedure.
   Boundary (base=invariant lifecycle; method=branch/prep/execution/review-how/decision-
   record) + B-injection + extend-cohesive-vs-cherry-pick-loose settled via grill; built &
   live-verified both tiers. base is delivery-only for now (discovery may get its own later).

3. **Repo rollout** — once discovery + the seeding feature are solid: apply discovery to
   real repos, migrate them to **devbox**, and file issues on **both ends** (beads inbox +
   GitHub). openlock is a reshape (stealth beads → committed inbox + GitHub backlog), not
   greenfield.

## Deferred, not forgotten

- **Exact beads sync config keys** — `bd hooks install` + Dolt-remote-over-git-origin is
  confirmed as the mechanism; the precise `bd config` knobs (auto-commit policy, ref
  layout) are pinned hands-on at the first real repo setup. The bundle names the
  behaviour, not the knobs.
- ~~`CLAUDE.local.md` seeding is manual~~ — **resolved** (task 1): the ruleset injects via
  the SessionStart hook; nothing is written into the repo but the one-line `.repo-visibility`
  marker. There is no `CLAUDE.local.md` seeding anymore.

## Housekeeping notes

- dotfiles design work was untracked at handover — commit
  `bundles/discovery.md`, `bundles/delivery.md`, `agents/`, `docs/` if not already done.
  Do **not** sweep in the unrelated `claude-code/settings.json` change
  (`workflowKeywordTriggerEnabled`, `theme`).
- umbel repo `docs/backlog.jsonl` is gitignored (local working state); the
  `CLAUDE.local.md` text calling it "checked-in" is slightly off — verify intent if it
  matters.
