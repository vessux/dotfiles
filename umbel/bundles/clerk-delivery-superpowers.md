---
name: clerk-delivery-superpowers
description: >-
  Superpowers delivery method on the Clerk delivery base: plan, test, verify, review, then finish with Clerk.
extends: [clerk-delivery-base]
skills:
  - superpowers/brainstorming
  - superpowers/dispatching-parallel-agents
  - superpowers/executing-plans
  - superpowers/finishing-a-development-branch
  - superpowers/receiving-code-review
  - superpowers/requesting-code-review
  - superpowers/subagent-driven-development
  - superpowers/systematic-debugging
  - superpowers/test-driven-development
  - superpowers/using-git-worktrees
  - superpowers/using-superpowers
  - superpowers/verification-before-completion
  - superpowers/writing-plans
  - superpowers/writing-skills
---

# clerk-delivery-superpowers

This method adds the superpowers discipline to `clerk-delivery-base`. Clerk owns the session loop
and reconciliation; superpowers owns the build craft between claim and submit.

The skills are listed directly rather than brought in through the upstream bundle so this generation
has exactly one SessionStart hook: `clerk-session-start`. If you need the superpowers refresher, open
`superpowers/using-superpowers`; it is available as a normal skill, not as an extra startup
announcement.

Use the superpowers skills for planning, test-driven work, verification, and review. Keep the Clerk
loop intact: claim first, build in the claimed workspace, submit with evidence, then run finish until
it converges or names the next action.
