# dotfiles

Personal dotfiles repo.

## Agent workflow

Use **Phyllary** (`phyllary`) as the workflow facade for this repo.

- Capture raw work with `phyllary capture`.
- Inspect/refine work with `phyllary inbox ...`.
- Pick up and deliver ready work with `phyllary backlog ...`.
- Run `phyllary doctor` when setup or the next workflow step is unclear.

Runtime instructions should speak Phyllary verbs only. Operator-only docs under `docs/agents/`
may describe lower-level storage details for maintenance.

## Domain docs

See `CONTEXT-MAP.md` for the local Umbel and external Phyllary contexts and their ADRs.
See `docs/agents/domain.md`.

## Agent skills

### Issue tracker

Work is tracked through Phyllary, not an external issue tracker. Use `phyllary capture`,
`phyllary inbox ...`, and `phyllary backlog ...`. See `docs/agents/issue-tracker.md`.

### Triage labels

The canonical triage roles map to Phyllary inbox/backlog dispositions, not tracker labels. See
`docs/agents/triage-labels.md`.

### Domain docs

This is a multi-context repo: see `CONTEXT-MAP.md` for context docs; root ADRs live in
`docs/adr/`. See `docs/agents/domain.md`.
