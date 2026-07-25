# dotfiles

Personal dotfiles repo.

## Agent workflow

Use **Clerk** (`clerk`) as the workflow facade for this repo.

- Capture raw work with `clerk capture`.
- Inspect/refine work with `clerk inbox ...`.
- Pick up and deliver ready work with `clerk backlog ...`.
- Run `clerk doctor` when setup or the next workflow step is unclear.

Runtime instructions should speak Clerk verbs only. Operator-only docs under `docs/agents/`
may describe lower-level storage details for maintenance.

## Domain docs

Multi-context; see `CONTEXT-MAP.md` for the documented Umbel and Clerk contexts and their ADRs.
See `docs/agents/domain.md`.

## Agent skills

### Issue tracker

Work is tracked through Clerk, not an external issue tracker. Use `clerk capture`,
`clerk inbox ...`, and `clerk backlog ...`. See `docs/agents/issue-tracker.md`.

### Triage labels

The canonical triage roles map to Clerk inbox/backlog dispositions, not tracker labels. See
`docs/agents/triage-labels.md`.

### Domain docs

This is a multi-context repo: see `CONTEXT-MAP.md` for context docs; root ADRs live in
`docs/adr/`. See `docs/agents/domain.md`.
