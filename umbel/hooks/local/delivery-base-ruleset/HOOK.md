---
name: delivery-base-ruleset
description: Inject the delivery System contract at session start, tier-selected from the committed repo-root .repo-visibility marker.
event: SessionStart
matcher: "startup|clear|compact"
command: ./inject
async: false
---

SessionStart hook for the `delivery-base` bundle. Reads the committed repo-root
`.repo-visibility` marker (`public` | `private`) via `git rev-parse --show-toplevel`
and injects the matching `seed.<tier>.md` — the **invariant delivery contract** every
method obeys (scope in → claim → capture-and-escalate → done, + a public review gate).

Identical machinery to the `discovery-ruleset` hook (the `inject` script differs only
in its `TRACK=` line). A delivery *method* (e.g. `delivery-superpowers`) extends
`delivery-base` and inherits this hook; it injects its own procedure hook only if its
skills don't already carry the method. The `.repo-visibility` marker is shared with
discovery.
