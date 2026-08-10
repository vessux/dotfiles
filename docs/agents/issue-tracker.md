# Issue tracker: Phyllary

Work for this repo uses a **Phyllary-backed backlog** through **Phyllary** (`phyllary`), not GitHub
Issues. Even though the remote is on GitHub, do **not** create GitHub issues for this repo's normal
workflow.

Phyllary is the workflow facade. Skills and agents should speak Phyllary verbs only; lower-level storage
or tracker details belong in operator-maintenance docs, not runtime instructions.

## Lifecycle

- **Raw capture / inbox item** — created with `phyllary capture "<title>"`.
- **Refinement** — inspect and shape inbox items with `phyllary inbox list`, `phyllary inbox show <id>`,
  `phyllary inbox dups`, `phyllary inbox pregrill <id> ...`, `phyllary inbox ready <id>`, and
  `phyllary inbox drop <id>`.
- **Ready for delivery** — an item promoted by `phyllary inbox ready <id>`. Ready means
  refinement-complete; it appears in `phyllary backlog next` only when it is currently pickable.
- **Waiting backlog work** — ready but not pickable because of open blockers or open direct
  children; inspect it with `phyllary backlog waiting` / `phyllary backlog show <id>`.
- **Delivery** — claim, resolve without code, submit, reconcile, or return work with
  `phyllary backlog ...` verbs.
- **Resolved or dropped** — Phyllary records the outcome through the relevant inbox/backlog verb.

Run `phyllary doctor` when setup or the next workflow step is unclear.

## When a skill says "publish to the issue tracker" / "create an issue"

Use `phyllary capture`, with a concise title and enough body/context for later refinement. Do not use
`gh issue create` for this repo.

Examples:

```bash
phyllary capture "two bundle seeds duplicate the same skill instructions" --stdin <<'EOF'
While editing one bundle, another carried a near-identical copy of the same skill guidance and the
two copies had already drifted. Options include factoring the shared text into one artifact or
leaving the copies until drift causes a real bug.
EOF
```

If the capture is already well-shaped and you are in a refinement pass, continue through
`phyllary inbox ...` rather than bypassing Phyllary.

## When a skill says "fetch the relevant ticket"

Use Phyllary:

- Inbox/refinement item: `phyllary inbox show <id>`
- Delivery-ready/backlog item: `phyllary backlog show <id>`

The user normally passes the Phyllary ID directly.

## When a skill says "break this into issues" or "publish tickets"

Create one Phyllary capture per vertical slice with `phyllary capture`, then refine those captures through
`phyllary inbox ...` until each keeper has explicit acceptance criteria and can be promoted with
`phyllary inbox ready <id>`. Blocked children may still be promoted once refined; blockers affect
backlog pickability, not readiness.

## Wayfinding operations

Use Phyllary's generic inbox graph primitives rather than raw tracker commands or a
workflow-specific namespace.

Wayfinder map cheat sheet when the user names a map by title instead of ID:

1. Find and inspect the map with `phyllary inbox list` and `phyllary inbox show <map-id>`.
2. Work the Refinement map frontier with `phyllary inbox frontier <map-id>` to see open, takeable
   children. Do not use `phyllary backlog next` here; that is only for delivery-ready work.
3. Claim a planning child with `phyllary inbox claim <ticket-id>`.
4. Resolve non-delivery planning work with `phyllary inbox resolve <ticket-id>`.
5. Update the map with `phyllary inbox update <map-id> ...` after reading the current `body_guard`.

Common operations:

- Create a map/epic: `phyllary capture "<map title>" --type epic --stdin`.
- Create direct children: `phyllary capture "<ticket title>" --parent <map-id> --type task --stdin`.
  The parent may be any non-closed Work graph item, including an already-ready spec/epic. Use
  canonical core types (`task`, `bug`, `feature`, `epic`, `chore`, `decision`) or configured custom
  types. Wayfinder ticket kind can live in the body or existing `wayfinder:<type>` labels; Phyllary's
  graph semantics do not depend on those labels.
- Wire sibling blockers: `phyllary inbox dep add <child> <blocker>`; remove with
  `phyllary inbox dep remove <child> <blocker>`. Dependency edges are only between siblings with the
  same immediate parent.
- Query a map: `phyllary inbox children <map-id>` for direct children, `phyllary inbox frontier <map-id>`
  for open, unassigned direct children whose blockers are all closed, `phyllary inbox blockers <id>`
  for what blocks an item, and `phyllary inbox blocked <id>` for what it blocks. These query verbs
  emit Phyllary-owned JSON by default; add `--pretty` for formatted JSON.
- Claim a planning ticket before work with `phyllary inbox claim <id>`; release an abandoned claim with
  `phyllary inbox release <id>`. A claimed ticket no longer appears in `phyllary inbox frontier`.
- Correct parentage: `phyllary inbox parent set <child> <parent>` or
  `phyllary inbox parent clear <child>`. If moving would leave invalid sibling-only dependency edges,
  rerun with `--drop-invalid-deps` only when dropping those edges is intended.
- Promote after refinement: planning graph items remain inbox items until `phyllary inbox ready <id>`
  records Acceptance criteria and marks them ready. It may promote blocked items and parents with
  open children; those ready items then leave `phyllary inbox list` / refinement frontier and appear in
  `phyllary backlog waiting` until blockers/children close. `phyllary backlog next`, `claim`, and
  `resolve` only use pickable ready work: open, unclaimed, no open blockers, no open direct
  children.
- Record planning progress with `phyllary inbox note <id> [--file <path>|--stdin]`.
- Resolve non-delivery planning items with `phyllary inbox resolve <id> [--file <path>|--stdin]`; it
  appends the resolution note and closes the inbox item without backlog promotion. Resolve a
  pickable ready backlog item that needs no code with
  `phyllary backlog resolve <id> [--returned keep|discard] [--file <path>|--stdin]`.
- Update a planning item with `phyllary inbox update <id> --title "..." --type <type>`. To replace the
  body, first read `body_guard` from `phyllary inbox show <id> --json`, then pass it with
  `--body-guard <guard>` alongside `--body-file <path>` or `--stdin`.

Do not create GitHub Issues. Do not use lower-level tracker commands in normal agent workflow.

## Triage state

See `docs/agents/triage-labels.md` for how Matt Pocock's canonical triage roles map to Phyllary
inbox/backlog dispositions.
