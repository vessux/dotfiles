---
name: glean
description: >-
  Use at the END of a work session (delivery OR discovery) to retrospectively harvest
  Impediments — workflow friction the agent hit and routed around but never captured in the
  moment: a denied permission, a command retried until it worked, a misfiring bundled skill, a
  missing or wrong doc, an MCP/tool error (e.g. worktree teardown failing at every delivery
  finish). Reads the session transcript (the unbiased record, surviving compaction), not the
  agent's memory, and files each as a `type:impediment` bead. Manual end-of-session ritual,
  like `/presort` and `/handoff`. Invoke as `/glean`.
---

# glean

You are running **`/glean`**: the retrospective session-harvester. Ambient capture is supposed
to file friction the instant it surfaces, but the agent is a biased witness to its own
session — it is optimised to finish the task, so it routes around an error and never files it.
Glean recovers exactly those missed signals from the **transcript**, which retains every
`is_error`, permission denial, and retry verbatim. Its discipline is **compound engineering**:
each session leaves leverage that cheapens the next. (Rationale + rejected alternatives:
`umbel/docs/adr/0012-glean-session-harvest-fork-that-writes.md`; terms **Glean** /
**Impediment**: `umbel/CONTEXT.md`.)

v1 gleans one category — the **Impediment** (`type:impediment`). The category list is open by
design: a new category is a detection rule + a new `type:*` value, **never** a new command.

## How it runs — a thin wrapper, then a fork

Glean is **two parts**: a sliver you (the main agent) run to locate this session's transcripts,
then a disinterested **fork** that reads them and files beads. The fork is needed because a
fresh reader is not anchored to your "I handled that fine" narrative, and parsing megabytes of
JSONL must stay out of your context. The wrapper is needed because a fork cannot know the
current session's UUID — only you can derive it.

### Part A — wrapper (you, in the main context)

1. **Derive the session UUID.** Your scratchpad path is given in your environment (the
   "Scratchpad Directory" section), shaped `…/<session-uuid>/scratchpad`. The **UUID is the
   directory name that directly contains `scratchpad`**.
2. **Locate this skill's extractor.** It is `scripts/extract.py` under this skill's base
   directory (the harness tells you the base directory when it loads this skill). Call it `$EXTRACT`.
3. **Sanity-check discovery** (cheap, read-only):
   ```bash
   python3 "$EXTRACT" --uuid <UUID> | head -c 400
   ```
   If `files_scanned` is 0, UUID derivation failed — **fall back to mtime**: the newest
   transcript is the session. Find it and use its UUID:
   ```bash
   ls -t ~/.config/claude-code/projects/*/*.jsonl ~/.claude/projects/*/*.jsonl 2>/dev/null \
     | head -1 | xargs -n1 basename | sed 's/\.jsonl$//'
   ```
4. **Dispatch ONE read-only fork.** Use the Agent tool, `subagent_type: general-purpose`.
   Hand it the **Fork brief** below *verbatim*, with `<UUID>` and `<EXTRACT path>` substituted.
   The fork inherits nothing — not your history, not skills, not the injected ruleset — so the
   brief is fully self-contained.
5. **Relay the fork's report** to the user: the filed bead IDs (one line each) and the
   candidates it excluded with why. Do not re-judge or re-file; the fork already filed.

Do **not** read the raw JSONL yourself (one session is ~megabytes across dozens of subagent
files; `Read` truncates and burns context). The extractor exists precisely to avoid this.

### Part B — Fork brief

> Paste everything in this block into the Agent prompt, substituting `<UUID>` and `<EXTRACT>`.
> It is written to the fork, in the second person.

```text
You are a disinterested GLEAN fork. You re-read a finished session's transcripts and file its
unfiled Impediments. You inherit nothing from the session that spawned you — work only from
what the extractor below gives you and what you read yourself. You are independent ON PURPOSE:
the main agent believed it "handled everything fine"; your job is to recover the friction it
filed away and forgot. Capture is ungated by design — you FILE directly, you never ask
permission per bead.

1. Run the extractor (deterministic parse; keeps the JSONL out of your context):
       python3 "<EXTRACT>" --uuid <UUID>
   It prints JSON: {"summary": {...}, "candidates": [...]}. Each candidate is one is_error
   tool_result joined to the command that caused it, with: source (main | subagent, plus
   agent_type/agent_description for subagents), tool, command, error_class
   (permission_denied | user_rejected | tool_error | runtime_error), error_excerpt,
   denial_reason, retry_count (times that same command ran this session), timestamp.

2. Apply the FIXABILITY TEST to every candidate. File it as an Impediment ONLY if BOTH hold:
     (a) a change to an instruction, skill, or tool would have PREVENTED it, AND
     (b) it would RECUR and cost tokens again unless something changes.
   The criterion is fixability, NOT the error flag.

   DO NOT rationalize friction away as "the guardrail worked" / "working as designed" /
   "expected safety refusal" / "the agent just slipped". A guardrail firing CORRECTLY and the
   agent WASTING a call on a blocked or wrong action are both true at once — the second is the
   fixable Impediment (an instruction could stop the agent attempting it). Your standing bias,
   inherited from the main agent, is to call friction "expected" and file nothing; that bias is
   the exact reason glean exists. When the evidence shows the agent was blocked, refused, or
   retried, the default is FILE, not skip.

   FILE (highest value = friction with OUR OWN injected rules / bundled skills / harness):
     - permission_denied / user_rejected — the agent was blocked and had to reroute.
     - a command retried to get past an error (retry_count >= 2, strongly >= 3).
     - a misfiring or wrong bundled skill; a missing or wrong doc the workflow relies on.
     - an MCP / tool error that recurs (e.g. worktree teardown refusing at every delivery
       finish; "File has not been read yet. Read it first" before Write/Edit).

   EXCLUDE (normal probing / one-offs — these are NOT Impediments):
     - an empty grep, a guard that fails, an exit code from a one-off exploratory command.
     - a one-off fat-finger: a typo'd command fixed on the next try, retry_count low, no sign
       it would recur (e.g. a SyntaxError in a throwaway scratch script).
     - runtime_error in a scratch/temp script you wrote and discarded.
   When torn, weight error_class + retry_count: permission_denied/user_rejected almost always
   qualify; tool_error often does (especially harness/recurring); runtime_error usually does
   NOT unless it recurs or implicates a bundled skill/instruction.

3. For each Impediment you keep, file a bead — EVIDENCE-RICH body, remediation LEFT OPEN.
   Your unique value is harvesting the perishable evidence before the session evaporates. Do
   NOT decide the fix: which instruction/skill/tool to change has more than one defensible
   answer — that is a later GRILL, not a capture-time call. Produce a well-evidenced grill
   candidate, not a solution.
     - Title (~80 chars): one-line summary of the friction. Name the tool/skill involved.
     - Body: quote the VERBATIM evidence — the failing command, the error_excerpt (and
       denial_reason if present), retry_count, WHERE it hit (main thread, or which subagent:
       agent_type + agent_description), and roughly what it cost. Then one line on WHY it is
       fixable (which instruction/skill/tool class is implicated) — without choosing the fix.
     - File it (multi-line body via stdin heredoc so quoting survives):
         bd create "<title>" -l type:impediment --body-file - --silent <<'BODY'
         <evidence-rich body>
         BODY
       (Single-line body is fine with -d "<body>" instead of --body-file -.)

4. You MAY Read/Grep/Glob repo files for context, but do NOT edit any repo file. Your only
   writes are `bd create`. Do not run any other bd write verb (no update/close/dep/set-state).

5. Report back (this is your entire output — it is data for the main agent, not a message to a
   human): the filed bead IDs, one line each ("dotfiles-xyz: <title>"); then the candidates you
   EXCLUDED, one line each with the reason, so the human can eyeball your calls.
```

## Scope — what glean does NOT do

- **No dedup / inbox-flood control.** Filing possibly-redundant impediments is fine; the
  "is this worth keeping / is it a duplicate" decision belongs to refinement, source-agnostically
  (dotfiles-o1o). Do not suppress a real impediment for fear of noise.
- **No cross-session analysis.** Glean is per-session by design. Reducing many `type:impediment`
  beads to a recurring-friction taxonomy + actionable instruction changes is **Gap B**
  (dotfiles-8vq), modelled on `plannotator/compound`, not part of `/glean`.

## Extending to new categories

The harvest *mechanism* (fork → read transcript → file typed captures) is category-agnostic.
Add a category by adding a detection rule to `scripts/extract.py` and a new `type:*` label
value — never a new command. Impediments are the beachhead; the list is open.
