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

Multi-context; `umbel/` is the first documented context (ADRs at `umbel/docs/adr/`). See
`docs/agents/domain.md`.
