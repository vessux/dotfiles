---
name: session-start
description: Autoload using-superpowers skill content at session start (introduces the superpowers skill set to the agent on startup/clear/compact).
event: SessionStart
matcher: "startup|clear|compact"
command: ./run-hook.cmd session-start
async: false
---

Ports obra/superpowers' SessionStart hook into seed-skills' named-hook artifact
shape. Two sidecar scripts:

- `run-hook.cmd` — verbatim from upstream; polyglot Windows/Unix dispatcher.
- `session-start` — patched at vendor time: `PLUGIN_ROOT` now reads from
  `${CLAUDE_PLUGIN_ROOT}` (set by CC when invoking the hook) instead of computing
  `${SCRIPT_DIR}/..`, because our cache layout puts the artifact one dir deeper
  than upstream's plugin layout.

Re-vendor on superpowers releases — copy `hooks/run-hook.cmd` and
`hooks/session-start` verbatim, re-apply the `PLUGIN_ROOT` patch on the
session-start script.

Vendored from obra/superpowers @ `f2cbfbef` (tag v5.1.0), captured 2026-05-20.
