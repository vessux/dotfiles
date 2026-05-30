---
name: plannotator
description: Visual review/annotate/explainer skills for Claude Code (backnotprop/plannotator)
skills:
  - plannotator/annotate
  - plannotator/last
---

# Plannotator

Skills-only bundle wrapping the plannotator binary's visual review surface.
No slash commands, no plan-mode hooks — if you want hook-driven plan-mode
interception, install the upstream marketplace plugin
(`/plugin marketplace add backnotprop/plannotator`) alongside.

## Skills

Auto-invokable:

- `plannotator-annotate` — annotate any markdown file, folder, or URL
- `plannotator-last` — annotate the latest assistant message

Trimmed to `annotate` + `last`. The wider plannotator surface (`review`,
`setup-goal`, `compound`, `visual-explainer`) still ships as source artifacts
under `~/.config/umbel/skills/plannotator/` — re-add to this bundle if needed.

## Prerequisite (host, one-time)

```bash
curl -fsSL https://plannotator.ai/install.sh | bash
```

Verify: `plannotator --version` (need `0.19.x` or later).

## Env

- `PLANNOTATOR_REMOTE=1` — SSH / devcontainer mode
- `PLANNOTATOR_PORT=<port>` — fixed port for forwarding
- `PLANNOTATOR_BROWSER` — override default browser
- `PLANNOTATOR_SHARE_URL` — self-hosted share portal

## Vendored from

backnotprop/plannotator @ `29390c9e7118` (tag `v0.19.18`), captured 2026-05-19.
Re-vendor on plannotator binary upgrades.
