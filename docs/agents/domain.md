# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the
codebase. This repo is **multi-context**: the `umbel/` subsystem is the first — and currently
only — documented context. "First", not "primary": it carries no special authority over other
areas; it's simply the first part of the repo to have earned ADRs and (eventually) a glossary.
More contexts get documented as they need it.

## Before exploring, read these

- **`CONTEXT-MAP.md`** at the repo root, if it exists — it points at one `CONTEXT.md` per context.
  Read the `CONTEXT.md` for the context you're working in.
- **`<context>/CONTEXT.md`** — currently `umbel/CONTEXT.md` for umbel-subsystem work.
- **`<context>/docs/adr/`** — read ADRs that touch the area you're about to work in. For umbel work
  that's **`umbel/docs/adr/`** (already populated). System-wide decisions, if any, live at the root
  `docs/adr/`.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest
creating them upfront. The producer skill (`/grill-with-docs`) creates them lazily when terms or
decisions actually get resolved. (As of setup: `umbel/docs/adr/` and `umbel/CONTEXT.md` exist; the
root `CONTEXT-MAP.md` does not yet.)

## File structure (multi-context)

```
/
├── CONTEXT-MAP.md                ← lists contexts (lazily created)
├── docs/adr/                     ← system-wide decisions, if any (lazily created)
└── umbel/                        ← the first documented context
    ├── CONTEXT.md                ← umbel domain glossary (EXISTS)
    └── docs/adr/                 ← umbel decisions (EXISTS)
        └── NNNN-*.md             ← numbered ADRs; list the dir to read them
```

The non-`umbel/` parts of this repo (zsh, nvim, tmux, git, … tool configs) carry no domain
language and need no `CONTEXT.md`.

## Use the glossary's vocabulary

When your output names a domain concept (a bead title, a refactor proposal, a hypothesis, a test
name), use the term as defined in the relevant `CONTEXT.md`. Don't drift to synonyms the glossary
explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing
language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0001 (discovery/delivery workflow) — but worth reopening because…_
