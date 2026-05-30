---
name: superpowers
description: Jesse Vincent's core skills library for Claude Code (TDD, debugging, collaboration patterns, planning workflows).
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
hooks:
  - superpowers/session-start
---

# Superpowers

Full mirror of [obra/superpowers](https://github.com/obra/superpowers)'s
core skill set at v5.1.0. Pure user-scope skills (no per-project state coupling),
so this bundle composes cleanly with other skill sets via `extends`.

## Skills (14)

Workflow and process:

- `brainstorming` — explore intent and design before any creative work
- `writing-plans` — turn a brief into a concrete implementation plan
- `executing-plans` — drive a plan to completion task-by-task
- `verification-before-completion` — verify before declaring done
- `finishing-a-development-branch` — wrap a branch for handoff or PR
- `using-git-worktrees` — work in parallel worktrees safely
- `using-superpowers` — meta-skill introducing the rest of the set

Engineering practice:

- `test-driven-development` — red-green-refactor with discipline
- `systematic-debugging` — root-cause loop, not symptom patching
- `writing-skills` — author new agent skills with progressive disclosure

Collaboration / multi-agent:

- `dispatching-parallel-agents` — spawn parallel subagents safely
- `subagent-driven-development` — delegate work to subagents
- `requesting-code-review` — ask another agent for review
- `receiving-code-review` — process review feedback

## Hooks

- `superpowers/session-start` — SessionStart hook that auto-injects the
  `using-superpowers` skill content at session start, so the agent knows the
  skill set is available without being asked.

## Vendored from

obra/superpowers @ `f2cbfbef` (tag `v5.1.0`), captured 2026-05-20.
Re-vendor on upstream release: clone the tagged repo, re-copy
`skills/*/` and `hooks/{run-hook.cmd,session-start}`, re-apply the
`PLUGIN_ROOT` patch documented in `~/.config/umbel/hooks/superpowers/session-start/HOOK.md`.
