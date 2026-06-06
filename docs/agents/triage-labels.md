# Triage Labels

This repo tracks issues in **beads**, not GitHub, so the five canonical triage roles map onto
beads **states** and **close-reasons** rather than GitHub labels. This is a **solo repo**, so the
mapping is deliberately simplified — `needs-info` and `ready-for-human` are folded away.

| Canonical role (mattpocock/skills) | beads mechanism |
| ---------------------------------- | --------------- |
| `needs-triage`    | An **open** bead with no `stage:*` label — a raw capture awaiting refinement. |
| `needs-info`      | *(not used)* — you are the reporter. Stays an open raw capture; add a `bd note <id>` if blocked on an external answer. |
| `ready-for-agent` | `bd set-state <id> stage=ready` (label `stage:ready`) — the AFK-ready handoff to the delivery track. |
| `ready-for-human` | *(not used)* — there is no separate human track. Anything ready becomes `stage:ready`; leave a `bd note` if a bead specifically needs you. |
| `wontfix`         | `bd close <id> --reason "wontfix: …"` — a closed bead whose reason records the drop. |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), perform the corresponding
beads action above. The one marker that matters day-to-day is **`stage:ready`** — the line between
a raw capture and work the delivery track can pull.

Note: `bd set-state <id> stage=ready` both records an event bead (the source of truth) and
maintains the `stage:ready` label as a fast-lookup cache.
