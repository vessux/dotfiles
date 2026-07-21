# Triage Labels

This repo tracks work through **Clerk**, so Matt Pocock's five canonical triage roles map to Clerk
inbox/backlog dispositions rather than GitHub labels.

| Canonical role (mattpocock/skills) | Clerk mechanism |
| ---------------------------------- | --------------- |
| `needs-triage` | An item shown by `clerk inbox list`: raw captured work that has not yet been promoted. |
| `needs-info` | Keep it in the inbox. Record the missing external fact in the item body, a pregrill note, or the refinement output; do not promote until the fact is available. |
| `ready-for-agent` | `clerk inbox ready <id>` after refinement has named the work and explicit acceptance criteria. Delivery then discovers it with `clerk backlog next`. |
| `ready-for-human` | Not a separate track in this repo. Keep it in the inbox when human judgment is still needed; use pregrill/refinement notes to state the decision. |
| `wontfix` | `clerk inbox drop <id>` with the reason. |

When a skill mentions applying a triage label, perform the corresponding Clerk disposition above.
The most important boundary is **inbox vs delivery-ready**: do not call something `ready-for-agent`
until `clerk inbox ready` can record acceptance criteria.

If setup or the next workflow step is unclear, run `clerk doctor` rather than dropping to lower-level
tracker commands.
