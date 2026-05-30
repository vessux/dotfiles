---
name: borklog
description: One-shot scaffolder that initializes borklog in a project — creates `docs/backlog.jsonl` + `docs/worklog.jsonl` and inserts a "Project memory" section into CLAUDE.md with the rules and schemas. Idempotent re-run for template updates. Use only when the user explicitly says "set up borklog", "init borklog", "scaffold borklog", "refresh borklog rules", or `/borklog`. NOT invoked for ongoing backlog/worklog operations — those run from CLAUDE.md after install. Solo author + single-agent design; not a multi-author issue tracker.
---

# borklog

Manual one-shot scaffolder for **borklog**: per-project shared memory between user and agent, expressed as two JSONL files plus a CLAUDE.md section that teaches future agents how to operate them.

## What this skill does

When invoked, the skill installs into the current project:

1. `docs/backlog.jsonl` — empty, if missing.
2. `docs/worklog.jsonl` — empty, if missing.
3. A `## Project memory` section in `CLAUDE.md` containing the borklog rules, bracketed with HTML comment markers (`<!-- borklog:start v1 -->` / `<!-- borklog:end v1 -->`) so future re-runs can update it in place without disturbing surrounding content.

The skill does **not** auto-trigger on backlog/worklog operations. After install, the rules in CLAUDE.md drive agent behavior every session.

## Procedure

1. **Verify project root.** Run `pwd`. If the user's intent is unclear (e.g., they invoked from a sub-directory), ask which directory should be the project root.

2. **Create data files (idempotent).** For each of `docs/backlog.jsonl`, `docs/worklog.jsonl`:
   - If missing → `mkdir -p docs && touch docs/<file>`.
   - If present → leave alone. Never overwrite.

3. **Locate `CLAUDE.md` in repo root** and pick insertion mode:
   - **No CLAUDE.md** → create it containing only the borklog section. Warn: this is a new file; the user likely wants to add other project context.
   - **Has CLAUDE.md, no `<!-- borklog:start vN -->` marker** → ask before appending. Show the user the section first; do not edit silently.
   - **Has markers, version matches `v1`** → already installed. Report and skip CLAUDE.md edit.
   - **Has markers, older version** → propose replacing content between markers; show diff first.

4. **Insert / replace** between the markers using the canonical template below — verbatim, including the marker lines.

5. **Report** what was created vs. left alone. State explicitly that the skill is dormant after install.

## Canonical CLAUDE.md template (v1)

Insert verbatim. The fenced code blocks inside this template are part of the section content; preserve their backticks.

````
<!-- borklog:start v1 -->
## Project memory

Two checked-in JSONL files:
- `docs/backlog.jsonl` — pending work. Mutable; delete on resolve.
- `docs/worklog.jsonl` — settled decisions. Append-only.

```
backlog: {"id":"bk-<ISO>","body":"...","refs":["..."]}
worklog: {"id":"<ISO>","title":"≤80c","decision":"...","rationale":"...","rejected":[...],"touches":[...],"reverses":"...","refs":["bk-..."]}
```

`id` = ISO timestamp. `bk-` prefix lets worklog cross-ref backlog.
Worklog required fields: `id`, `title`, `decision`.

### Backlog rules

Discovered work mid-task → append. Don't ask. Body self-contained:
symptom, bound, proposed fix, revisit trigger.

Write-path dedup: pick 2–3 distinctive keyword stems (proper nouns,
file paths, error strings — not verbs) → `grep -i` each against
`docs/backlog.jsonl` → on hit, read body and decide skip/merge/distinct.
If unsure, append with `(possible dup of bk-X)`.

Read-path dedup: when reading the whole file for any reason, flag
near-dupes before completing the requested op. Ask before merging.

Delete on resolve. Rationale worth preserving migrates to a worklog
entry whose `refs[]` lists the deleted `bk-id`.

Example:
```
{"id":"bk-2026-04-29T08:14:00Z","body":"cleanSession network teardown stalls ~10s when called while pypi/npm sidecar background promises are in-flight AND workload uses --userns=keep-id. Pre-keep-id race completed in ~1s; keep-id amplifies 10x. Likely podman/aardvark-DNS × userns interaction. Production impact bounded; instrument cleanSession to await backgroundReady before network teardown. Surfaced when bun afterAll's 5s default fired in slice-5 integration tests."}
```

### Worklog rules

Append iff future-agent reading code + git log alone would miss it.
Two valid gaps:
- **Non-diffable** — rejected alternatives, negative results,
  empirical probes, belief snapshots, reversals.
- **Compressive** — slice open/close, cross-commit design calls.

"Commit changed X to do Y" → commit message, not worklog.

Example:
```
{"id":"2026-04-27T20:34:37Z","title":"slice 8.4 pre-flight: narrow scope to workload-only","decision":"Drop subslice 8.4c (sidecar non-root + cap_net_bind_service); keep workload-only changes.","rationale":"Sidecar non-root has unsolved 0600 host-bind-mount problem.","rejected":["ship 8.4 with sidecar useradd + USER + cap_net_bind_service — breaks per-session leaf private-key reads","--userns=keep-id on sidecars — reverses earlier plan decision","relax host bind perms to 0640 — brittle across macOS/Linux"],"touches":["docs/architecture.md"]}
```

### Scope

Solo + single-agent. Not a multi-author issue tracker. Backlog
past ~200 entries = workflow leak, not file problem.
<!-- borklog:end v1 -->
````

## Honest scope

One-shot scaffolder. Does not fire on backlog/worklog operations across sessions — that's CLAUDE.md's job after install.

If the template improves in future skill versions (`v2`, `v3`…), existing projects keep the old version until the user re-runs `/borklog` and accepts the diff. Manual maintenance over invisible drift.

The pattern is designed for solo + single-agent collaboration. Flat-file dedup and JSONL append-only break under merge-heavy multi-author workflows. If a project crosses ~4 humans editing the files, switch to a real issue tracker.
