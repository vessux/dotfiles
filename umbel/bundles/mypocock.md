---
name: mypocock
description: plannotator (annotate+last) + pocock + tuidriver MCP
extends: [plannotator, pocock]
mcps:
  - local/tuidriver
---

# mypocock

Project bundle: the Matt Pocock skill set and the plannotator annotate/last
review surface, plus the `tuidriver` MCP.

Composes the user-scope library bundles via `extends`; `tuidriver` is added
directly as an MCP (no dedicated bundle by design — single MCP).

Prereqs: `plannotator` and `tuidriver` binaries on `PATH`.
