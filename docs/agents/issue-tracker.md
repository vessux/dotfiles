# Issue tracker: Clerk

Work for this repo is tracked through **Clerk** (`clerk`), not GitHub Issues. Even though the
remote is on GitHub, do **not** create GitHub issues for this repo's normal workflow.

Clerk is the workflow facade. Skills and agents should speak Clerk verbs only; lower-level storage
or tracker details belong in operator-maintenance docs, not runtime instructions.

## Lifecycle

- **Raw capture / inbox item** — created with `clerk capture "<title>"`.
- **Refinement** — inspect and shape inbox items with `clerk inbox list`, `clerk inbox show <id>`,
  `clerk inbox dups`, `clerk inbox pregrill <id> ...`, `clerk inbox ready <id>`, and
  `clerk inbox drop <id>`.
- **Ready for delivery** — an item promoted by `clerk inbox ready <id>` and visible to delivery via
  `clerk backlog next` / `clerk backlog show <id>`.
- **Delivery** — claim, submit, reconcile, or return work with `clerk backlog ...` verbs.
- **Resolved or dropped** — Clerk records the outcome through the relevant inbox/backlog verb.

Run `clerk doctor` when setup or the next workflow step is unclear.

## When a skill says "publish to the issue tracker" / "create an issue"

Use `clerk capture`, with a concise title and enough body/context for later refinement. Do not use
`gh issue create` for this repo.

Examples:

```bash
clerk capture "two bundle seeds duplicate the same skill instructions" --stdin <<'EOF'
While editing one bundle, another carried a near-identical copy of the same skill guidance and the
two copies had already drifted. Options include factoring the shared text into one artifact or
leaving the copies until drift causes a real bug.
EOF
```

If the capture is already well-shaped and you are in a refinement pass, continue through
`clerk inbox ...` rather than bypassing Clerk.

## When a skill says "fetch the relevant ticket"

Use Clerk:

- Inbox/refinement item: `clerk inbox show <id>`
- Delivery-ready/backlog item: `clerk backlog show <id>`

The user normally passes the Clerk ID directly.

## When a skill says "break this into issues" or "publish tickets"

Create one Clerk capture per vertical slice with `clerk capture`, then refine those captures through
`clerk inbox ...` until each keeper has explicit acceptance criteria and can be promoted with
`clerk inbox ready <id>`.

Do not create GitHub Issues. Do not use lower-level tracker commands in normal agent workflow.

## Triage state

See `docs/agents/triage-labels.md` for how Matt Pocock's canonical triage roles map to Clerk
inbox/backlog dispositions.
