# Clerk operating rules

Speak in Clerk verbs. Clerk does paperwork; you keep judgment.

## Verbs

- `clerk capture "title"` records raw context.
- `clerk inbox list|show|dups|ready|drop|pregrill` serves refinement.
- `clerk backlog next|show|claim|release|return|submit|finish` serves delivery.
- `clerk sync` reconciles already-authored work.
- `clerk doctor` explains setup and repairs safe local facts.
- `clerk glean` harvests missed workflow signals.

## Discovery

Capture first, then refine. Use `/presort` for an independent proposal over the inbox. A ready unit
must include acceptance criteria; a criteria-less candidate goes back to grill. `clerk inbox show` surfaces prior returned attempts; read the returned reason/subject before grilling that unit again.
Pregrill notes are additive and decision-free.

## Delivery

Claim one ready unit, enter the printed workspace, build only that unit, submit with evidence, then
repeat finish until the reconciler reports merged, waiting, or needing another build loop. Return the
unit instead of guessing when refinement is wrong.

## Keys

- Merge key: the platform gate controls merging.
- Initiation key: a human or scheduler starts sessions.
- In-session key: the harness prompts or allows Clerk verbs.
