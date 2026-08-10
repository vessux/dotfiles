# Triage Labels

This repo tracks work through **Phyllary**, so Matt Pocock's five canonical triage roles map to Phyllary
inbox/backlog dispositions rather than GitHub labels.

| Canonical role (mattpocock/skills) | Phyllary mechanism |
| ---------------------------------- | --------------- |
| `needs-triage` | An item shown by `phyllary inbox list`: raw captured work that has not yet been promoted. |
| `needs-info` | Keep it in the inbox. Record the missing external fact in the item body, a pregrill note, or the refinement output; do not promote until the fact is available. |
| `ready-for-agent` | `phyllary inbox ready <id>` after refinement has named the work and explicit acceptance criteria. Pickable work appears in `phyllary backlog next`; blocked ready work appears in `phyllary backlog waiting`. |
| `ready-for-human` | Not a separate track in this repo. Keep it in the inbox when human judgment is still needed; use pregrill/refinement notes to state the decision. |
| `wontfix` | `phyllary inbox drop <id>` with the reason. |

When a skill mentions applying a triage label, perform the corresponding Phyllary disposition above.
The most important boundary is **inbox vs delivery-ready**: do not call something `ready-for-agent`
until `phyllary inbox ready` can record acceptance criteria.

If setup or the next workflow step is unclear, run `phyllary doctor` rather than dropping to lower-level
tracker commands.
