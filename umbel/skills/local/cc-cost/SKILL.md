---
name: cc-cost
description: >
  Token-usage and API-price cost report for Claude Code work — the current session, a
  background task/subagent, a workflow run, or a past session. Resolves the right
  transcript JSONL paths and runs the stowed `cc-cost` script on them. Use when asked
  what a session/workflow/task cost, how many tokens something burned, or for a
  usage/cost breakdown.
---

# cc-cost — transcript cost reporting

The calculator is the `cc-cost` script (dotfiles `bin/`, stowed onto PATH). It owns the
two things worth owning: **dedupe** (transcripts repeat a message's usage across lines —
streaming snapshots and multi-block messages share one `message.id`; the script keeps one
final snapshot per id, naive line-summing over-counts input roughly 2x) and the **price
sheet** (hardcoded per-MTok with an as-of date it prints itself). Never sum transcript
usage lines by hand, and never quote prices from memory — if prices look stale, update
the table at the top of the script, nowhere else.

## Resolve the scope to transcript paths

Project transcript root: `~/.config/claude-code/projects/<slug>/` where `<slug>` is the
session's working directory with each `/` replaced by `-`
(`/home/kovis/dotfiles` → `-home-kovis-dotfiles`).

| Asked about | Pass to cc-cost |
|---|---|
| current session, main loop only | newest `*.jsonl` directly in the project root — the live file, mtime sorts it first |
| current session including everything it spawned | that file **plus** the sibling directory named by the session UUID (`<root>/<uuid>/` — subagents and workflows live under its `subagents/`) |
| a workflow run | `<root>/<uuid>/subagents/workflows/<run-id>/` — the `wf_…` run id and full transcript dir are printed in the Workflow tool result |
| a background task / subagent | its `agent-*.jsonl` under `<root>/<uuid>/subagents/` — the task result names the transcript path; given only a task id, grep the subagents dir for it |
| a past session | find its UUID by grepping the project root for a phrase unique to that conversation, then pass its file + UUID-dir pair |

When the newest-file heuristic matters (several recent sessions), verify by grepping the
candidate for a phrase from the current conversation before reporting.

## Invoke and present

```
cc-cost <paths…>        # human table (per model x direction, totals, savings)
cc-cost --json <paths…> # raw aggregation for post-processing
cc-cost --no-price …    # token counts only
```

- Paths can mix files and directories; directories are scanned recursively for `*.jsonl`.
- Show the table as-is — it is already formatted and carries the prices-as-of warning.
  Add at most a line or two of interpretation (what dominates the cost, cache savings).
- Main-loop and subagent tokens bill separately: an unqualified "what did this session
  cost" means the session file **and** its UUID directory together.
- The current session's own file is still being appended; the report is a snapshot as of
  invocation, and the turn answering the question isn't fully in it yet.
