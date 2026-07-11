---
name: clerk-session-start
description: Inject concise Clerk operating rules at session start and start an async glean sweep.
event: SessionStart
matcher: "startup|clear|compact"
command: ./session-start
async: false
---

SessionStart hook for the Clerk generation. It injects one concise Clerk grammar seed and starts
`clerk glean --async` without waiting for harvest work. The hook is shared by discovery and delivery
bundles; track shape comes from the verbs the session uses, not from separate hook copies.
