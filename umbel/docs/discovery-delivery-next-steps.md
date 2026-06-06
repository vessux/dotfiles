# discovery / delivery — handover (clean session)

**STATUS (2026-06-02): adoption INFRA DONE on `umbel`.** Committed on branch
`chore/adopt-discovery-delivery-workflow` @70db1cd (NOT pushed; cookbook left uncommitted):
`.repo-visibility=public`; worklog distilled into `docs/adr/0001-0006`+README (worklog.jsonl
kept as gitignored archive); 8 backlog items imported into the beads inbox (prefix `umbel-`,
P1 shim-publish `umbel-1dd`, P2 YAML papercut `umbel-244`, P3×6 multi-harness epic) with
`backlog.jsonl` kept as a gitignored archive; PR template added; **CLAUDE.local.md removed**
(process is injected); **discovery pinned** (`.umbel-bundle`).
**beads is GIT-REMOTE-BACKED VIA DOLT** (normal mode, NOT stealth): Dolt remote `origin` =
`git+https://github.com/vessux/umbel.git`, `bd dolt push` → `refs/dolt/data` (verified on the
remote). `export.git-add=false`; `.beads/config.yaml`+`metadata.json` committed, the Dolt DB +
`issues.jsonl` + logs gitignored. The discovery "Wire beads" step was rewritten to this model
(it was vague and caused a jsonl-in-git mis-step); crisp version in auto-memory
`beads-git-backing-model`.
**Remaining:** (1) dogfood — plain `claude` → triage inbox → GitHub Issues; swap pin to
`delivery-superpowers` → land the cookbook PR, then fix YAML papercut `umbel-244` in
`src/bundle/discover.ts`; (2) push/merge the branch; (3) optional `bd hooks install` (auto
`bd dolt push/pull` on git push/pull) — not run. The plan below is the original mission record.

Auto-memory (`discovery-delivery-workflow`) is the short bridge; this is the depth.

## Ready to use (built, live-verified, committed)

All in `~/.config/umbel` (= dotfiles; committed `f9119bc`):
- **discovery** — capture/refine (renamed from capture/triage/prep, ADR 0003). `bundles/discovery.md` + `hooks/local/discovery-ruleset/` + `agents/local/presort` + `local/tuidriver` MCP.
- **delivery-base** — the invariant contract (scope → claim → capture-and-escalate-never-decide → done, + public review gate) + shared tooling (annotate/last, grill-with-docs, tuidriver). `bundles/delivery-base.md` + `hooks/local/delivery-base-ruleset/`.
- **delivery-superpowers** — first method: `extends: [delivery-base, superpowers]`, no custom hook (superpowers' own announce-hook + skills carry prep+execution).

**How rules reach the agent:** a SessionStart hook reads a committed repo-root
`.repo-visibility` (`public`|`private`) and injects the tier-matched ruleset as
`additionalContext` (re-fires on `compact`). **Nothing is written into the project tree
but that one-line marker.** umbel itself is unchanged — it's all bundle artifacts.

Design of record: ADR `~/.config/umbel/docs/adr/0001` (workflow) + `0002` (delivery
base/method). The INJECT-not-SEED reversal: umbel `docs/worklog.jsonl` @
2026-06-01T09:29:20Z. Authoring patterns: `~/Work/personal/umbel/docs/cookbook.md`.

**The bundles' "Applying this bundle" sections are the source of truth for adoption —
read them** (`~/.config/umbel/bundles/{discovery,delivery-base,delivery-superpowers}.md`).
This handover only adds umbel-specifics.

## Adopting on umbel — the plan (public tier, reshape)

1. **Tier = public.** Write `public` to a committed `.repo-visibility` at the umbel repo root.
2. **beads inbox.** `bd init` + `bd hooks install` (sync over the repo's own git origin). Exact config keys: pin hands-on (deferred).
3. **Decision record = ADRs.** The umbel repo has **no `docs/adr/` yet** — the 0001/0002 ADRs live in *dotfiles*, a different repo. Create `docs/adr/` in the umbel repo; add a PR-template "architectural change? link the ADR" prompt. Public tier = **no committed worklog**.
4. **Migrate the borklog backlog.** `docs/backlog.jsonl` (gitignored; 8 items — 6 multi-harness adapters, 1 shim-publish `bk-2026-05-30T14:50:52Z`, 1 YAML-parse papercut `bk-2026-06-01T09:59:33Z`) → `bd q` into the inbox → triage → flesh kept ones into **GitHub Issues** (Pocock `to-prd`) and close the bead; drop the rest.
5. **Worklog — FLAG (decision to make).** `docs/worklog.jsonl` (gitignored) holds private design archaeology (the v0→v2.1 prehistory the history-squash hid, plus this session's reversals). Public tier has no committed worklog. **Recommend: freeze it as a private, still-gitignored archive — do NOT migrate entries into public ADRs** (would expose rejected-alternative archaeology + prehistory). Go-forward decisions → ADRs only.
6. **CLAUDE.local.md.** It currently carries the borklog "Project memory" rules. Operating rules are now *injected*, and the backlog/worklog convention is being replaced (beads + GitHub + ADRs). Replace/trim that section; keep committed `CLAUDE.md` as the contributor face. (Note: umbel's CLAUDE.local.md still calls borklog "checked-in" while it's gitignored — stale; reconcile.)
7. **Pin + run.** `umbel apply discovery` (to triage the migrated inbox), then `delivery-superpowers` (to build). The PATH shim routes plain `claude`.

## Good first real units (dogfood the workflow)
- **Land the cookbook:** `docs/cookbook.md` + the README/spec link edits are **uncommitted** on umbel `main`. umbel uses **PR flow** → first GitHub issue → `delivery-superpowers` → PR. A clean first exercise.
- **YAML-parse papercut** (`bk-2026-06-01T09:59:33Z`): a real `src/bundle/discover.ts` task → issue → fix (surface a bundle's frontmatter parse error in `list`/`build` instead of silently dropping it).

## Deferred / watch
- Exact beads sync config keys — hands-on at first setup.
- discovery may get its own base later (`delivery-base` is delivery-only).
- Shim relocation (`bk-2026-05-30T14:50:52Z`) is **breaking** at the next npm publish — note the path move + re-run `umbel shim install`.
- Uncommitted in dotfiles: `claude-code/settings.json` (leave — unrelated) and this handover edit.

## Pointers
- Bundles + playbooks: `~/.config/umbel/bundles/{discovery,delivery-base,delivery-superpowers}.md`
- ADRs: `~/.config/umbel/docs/adr/{0001-discovery-delivery-workflow,0002-delivery-base-and-swappable-methods}.md`
- Composition trail (discovery): `~/.config/umbel/docs/discovery-bundle-composition.md`
- Cookbook (umbel, public): `~/Work/personal/umbel/docs/cookbook.md`
- umbel worklog (INJECT decision + rejected alternatives): `~/Work/personal/umbel/docs/worklog.jsonl`
