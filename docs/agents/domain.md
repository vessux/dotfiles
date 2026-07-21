# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the
codebase. This repo is **multi-context**: `umbel/` is the first documented context, with more
contexts added only when they need their own vocabulary or decisions.

## Before exploring, read these

- **`CONTEXT-MAP.md`** at the repo root, if it exists — it points at one `CONTEXT.md` per context.
  Read the `CONTEXT.md` for the context you're working in.
- **`<context>/CONTEXT.md`** — currently `umbel/CONTEXT.md` for Umbel subsystem work.
- **`<context>/docs/adr/`** — read ADRs that touch the area you're about to work in. For Umbel work
  that's **`umbel/docs/adr/`**. System-wide decisions live at **`docs/adr/`**.

If any of these files don't exist, proceed silently. The producer skills create them lazily when a
term or decision is actually resolved.

## File structure (multi-context)

```
/
├── CONTEXT-MAP.md                ← lists contexts (lazily created)
├── docs/adr/                     ← system-wide decisions
└── umbel/                        ← first documented context
    ├── CONTEXT.md                ← Umbel glossary
    └── docs/adr/                 ← Umbel decisions
        └── NNNN-*.md             ← numbered ADRs; list the dir to read them
```

Most non-`umbel/` dotfile areas (zsh, nvim, tmux, git, etc.) carry no domain language yet and need
no `CONTEXT.md` until a real vocabulary or decision record emerges.

## Use the glossary's vocabulary

When your output names a domain concept — a Clerk capture title, refactor proposal, hypothesis, or
test name — use the term as defined in the relevant `CONTEXT.md`. Don't drift to synonyms the
glossary explicitly avoids.

If the concept you need isn't in the glossary yet, either reconsider whether you're inventing
language the project doesn't use, or note the gap for `/grill-with-docs` / `/domain-modeling`.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0001 (discovery/delivery workflow) — but worth reopening because..._
