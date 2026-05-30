---
name: mysuperpowers
description: plannotator (annotate+last) + superpowers + tuidriver MCP
extends: [plannotator, superpowers]
mcps:
  - local/tuidriver
---

# mysuperpowers

Project bundle: the full superpowers skill set (+ its SessionStart hook) and
the plannotator annotate/last review surface, plus the `tuidriver` MCP.

Composes the user-scope library bundles via `extends`; `tuidriver` is added
directly as an MCP (it has no dedicated bundle by design — single MCP).

Prereqs: `plannotator` and `tuidriver` binaries on `PATH`.
