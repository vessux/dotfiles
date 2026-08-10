---
name: phyllary-session-start
description: Inject concise Phyllary operating rules at session start and start an async glean sweep.
event: SessionStart
matcher: "startup|clear|compact"
command: ./session-start
async: false
---

SessionStart hook for the Phyllary generation. It injects one concise Phyllary grammar seed and starts
`phyllary glean --async` without waiting for harvest work. The hook is shared by discovery and delivery
bundles; track shape comes from the verbs the session uses, not from separate hook copies.
