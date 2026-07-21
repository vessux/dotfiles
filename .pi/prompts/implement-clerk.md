---
description: Invoke /skill:implement for a Clerk backlog unit using this repo's delivery workflow
argument-hint: "[clerk-id]"
---
/skill:implement Implement Clerk backlog unit ${1:-the next ready unit}.

Follow this repo's Clerk workflow:

1. Run `clerk doctor` if setup or the next workflow step is unclear.
2. If a Clerk ID was supplied in this prompt (`$1`), inspect it with `clerk backlog show <id>`; otherwise run `clerk backlog next`, pick one ready unit, and inspect it with `clerk backlog show <id>`.
3. Claim the unit with `clerk backlog claim <id>`.
4. Do all implementation work inside the created `.worktrees/<id>` worktree, not the repo root.
5. Implement only that backlog unit and satisfy its acceptance criteria; use TDD/test-first where practical.
6. Run the relevant checks/tests.
7. Use `/skill:code-review` or the code-review skill to review the completed diff before submit.
8. Generate proof with `clerk backlog proof <id>`, fill in evidence for every acceptance criterion, then submit with `clerk backlog submit <id> <proof.json>`.
9. If the unit is impossible as written, use `clerk backlog return <id> --reason "..."` rather than improvising scope.
