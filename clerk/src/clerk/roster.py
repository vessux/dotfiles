"""Public Clerk command roster and explain text."""

from __future__ import annotations

from collections.abc import Iterable, Sequence

ADR15 = "ADR 0015 — clerk/docs/adr/0015-clerk-opaque-workflow-verb-facade.md"
ADR16 = "ADR 0016 — umbel/docs/adr/0016-delivery-gate-acceptance-proof-and-judgment-loops.md"
ADR17 = "ADR 0017 — clerk/docs/adr/0017-tier-retired-backlog-location-and-merge-gate-axes.md"

TOP_LEVEL_VERBS = ("capture", "sync", "doctor", "glean")
NOUN_VERBS: dict[str, tuple[str, ...]] = {
    "inbox": (
        "list",
        "show",
        "dups",
        "ready",
        "drop",
        "pregrill",
        "children",
        "frontier",
        "blockers",
        "blocked",
        "parent",
        "dep",
        "claim",
        "release",
        "note",
        "update",
        "resolve",
    ),
    "backlog": (
        "next",
        "show",
        "waiting",
        "claim",
        "release",
        "resolve",
        "proof",
        "submit",
        "gate",
        "finish",
        "return",
    ),
}

ROSTER_LINES = (
    "Known verbs:",
    '  capture "<title>" [--stdin|--type <type>|--impediment|--parent <id>|--blocked-by <id>]',
    "  inbox list|show|dups|ready|drop|pregrill|children|frontier|blockers|blocked|parent|dep|claim|release|note|update|resolve",
    "  backlog next|show|waiting|claim|release|resolve|proof|submit|gate|finish|return",
    "  sync",
    "  doctor [--fix --backend bd|gh]",
    "  glean",
    "Next: run 'clerk --explain <verb>' to see what a verb does.",
)

EXPLAIN_TEXT: dict[str, tuple[str, ...]] = {
    "capture": (
        "clerk capture — file one raw capture into the bd inbox",
        '  usage: clerk capture "<title>" [--stdin|--type <type>|--impediment|--parent <id>|--blocked-by <id>...]',
        '  runs: bd create "<title>" [--stdin] [--type ...] [--parent ...] [--deps ...]           (backlog: bd|gh)',
        "        (GitHub-backed repos use GitHub only after inbox ready promotion)",
        f"  see:  {ADR15}",
    ),
    "sync": (
        "clerk sync — reconcile every open claim (authorship-free phases only)",
        "  runs: gh pr view --json state,mergedAt per open claim; then bd close / bd update",
        "        (backlog: bd) or gh issue close / gh issue edit (backlog: gh) per reconciled",
        "        state; reclaims stale claims; files reports for judgment-needing states",
        f"  see:  {ADR15}",
    ),
    "doctor": (
        "clerk doctor — check and provision workflow plumbing",
        "  runs: git rev-parse --show-toplevel; reads .clerk; command -v bd vs the shim locations; gh auth status",
        "        --fix --backend bd|gh writes the .clerk marker",
        f"  see:  {ADR17}",
    ),
    "glean": (
        "clerk glean — watermark sweep of session transcripts into captures",
        "  runs: flock-guarded sweep over per-transcript line offsets (state in ~/.local/state/clerk/); spawns the judgment fork per unharvested chunk",
        f"  see:  {ADR15}",
    ),
    "inbox list": (
        "clerk inbox list — list the unrefined bd capture pool",
        "  usage: clerk inbox list [--limit <n>]",
        "  runs: bd list, filtered to open minus stage:ready         (backlog: bd|gh)",
        "        --limit forwards to bd; 0 = unlimited",
        f"  see:  {ADR15}",
    ),
    "inbox show": (
        "clerk inbox show — show one bd-backed inbox item",
        "  usage: clerk inbox show <id> [--json|--pretty]",
        "  runs: bd show <id>          (backlog: bd|gh)",
        f"  see:  {ADR15}",
    ),
    "inbox dups": (
        "clerk inbox dups — cluster duplicate bd captures for pre-sort",
        "  runs: bd duplicates         (backlog: bd|gh)",
        f"  see:  {ADR16}",
    ),
    "inbox ready": (
        "clerk inbox ready — write refinement output, then promote a groomed bd capture",
        "  usage: clerk inbox ready <id> [--design-file <path>] [--acceptance-file <path>] [--returned keep|discard]",
        '         (gh: --title "<title>" --body-file <path>)',
        "  runs: for bd, optional bd update --design-file / --acceptance, then refuses",
        "        units still lacking acceptance criteria (ADR 0016); if returned/<id> exists,",
        "        requires --returned keep|discard before stage:ready; for gh, creates a",
        "        GitHub issue labelled ready-for-agent, then closes the bd capture as promoted",
        f"  see:  {ADR16}",
    ),
    "inbox drop": (
        "clerk inbox drop — close a bd capture as not worth doing",
        "  usage: clerk inbox drop <id> [--returned keep|discard]",
        "  runs: if returned/<id> exists, requires --returned keep|discard; discard deletes",
        "        that evidence branch, keep preserves it; then bd close <id> --reason wontfix",
        "        (backlog: bd|gh)",
        f"  see:  {ADR16}",
    ),
    "inbox pregrill": (
        "clerk inbox pregrill — append prep notes onto a bd capture before its grill",
        '  runs: bd update <id> --notes "<dated, state-neutral prep note>"    (backlog: bd|gh)',
        "        note carries open decisions, premises with suggested verifications, draft criteria",
        f"  see:  {ADR16}",
    ),
    "backlog next": (
        "clerk backlog next — pick the next pickable ready unit",
        "  runs: bd list --status open --label stage:ready --no-assignee --readonly --json, then filters no open blockers/children     (backlog: bd)",
        "        gh issue list --label ready-for-agent              (backlog: gh)",
        f"  see:  {ADR17}",
    ),
    "backlog show": (
        "clerk backlog show — show one backlog unit",
        "  runs: bd show <id>          (backlog: bd)",
        "        gh issue view <id>    (backlog: gh)",
        f"  see:  {ADR15}",
    ),
    "backlog waiting": (
        "clerk backlog waiting — list refined-ready work that is waiting on graph state",
        "  runs: bd list --status open --label stage:ready --no-assignee --readonly --json, then reports open blocker/child counts     (backlog: bd)",
        "        gh issue list --label ready-for-agent              (backlog: gh; no graph waiting view yet)",
        f"  see:  {ADR17}",
    ),
    "backlog claim": (
        "clerk backlog claim — take the claim lock on a unit",
        "  usage: clerk backlog claim <id> [--from-returned|--fresh --returned keep|discard]",
        "  runs: refuses units with no Acceptance Criteria section (ADR 0016 C4); short-circuits",
        "        if you already hold it; else git push of the canonical delivery/<id> branch",
        "        (first push wins — the universal CAS lock, exit 5 if occupied or the race is",
        "        lost); on success, bd update <id> --claim as the online fast-path record",
        "        (backlog: bd); offline: local-only branch + claim, attended only; finally",
        "        git worktree add .worktrees/<id>, printing its absolute path; with returned/<id>,",
        "        plain claim refuses until you choose --from-returned (reuse and keep evidence)",
        "        or --fresh --returned keep|discard (start from main explicitly)",
        f"  see:  {ADR17}",
    ),
    "backlog release": (
        "clerk backlog release — give a claim back without finishing (unit stays stage:ready)",
        "  runs: refuses if delivery/<id> carries commits beyond main (prescribes submit or",
        "        return instead); else git worktree remove + git branch -D delivery/<id>,",
        "        plus git push origin --delete delivery/<id> when reachable; then",
        '        bd update <id> --status open --assignee ""        (backlog: bd)',
        "        gh issue edit <id> --remove-assignee              (backlog: gh)",
        "        offline: local teardown only, remote delete deferred to sync; job-context refuses;",
        "        idempotent (exit 0) on a unit not claimed here",
        f"  see:  {ADR15}",
    ),
    "backlog resolve": (
        "clerk backlog resolve — close a pickable ready unit without delivery code",
        "  usage: clerk backlog resolve <id> [--returned keep|discard] [--file <path>|--stdin]",
        '  runs: refuses non-pickable/claimed units and criteria-less units; appends a non-empty resolution note; bd close --reason "resolved without delivery"     (backlog: bd)',
        f"  see:  {ADR16}",
    ),
    "backlog proof": (
        "clerk backlog proof — print the JSON proof skeleton consumed by submit",
        "  usage: clerk backlog proof <id>",
        "  runs: bd show <id> --readonly --json / gh issue view <id>, then prints proof-only JSON:",
        '        {"acceptance":[{"text":"<normalized criterion>","evidence":""}]}',
        f"  see:  {ADR16}",
    ),
    "backlog submit": (
        "clerk backlog submit — open the unit's PR (once per unit; iteration repeats finish)",
        "  usage: clerk backlog submit <id> <proof.json|->   (legacy: --body-file <path>)",
        "  runs: consumes proof JSON, renders the PR body with the unit criteria and Clerk-run checks, runs clerk backlog gate as a local preflight, pushes delivery/<id>, then gh pr create; never arms auto-merge",
        f"  see:  {ADR16}",
    ),
    "backlog gate": (
        "clerk backlog gate — validate delivery proof classes C1-C4",
        "  runs: C1 branch/link/current protocol checks; C2 PR-body verification schema check; C3 bats tests/clerk (parallel with --jobs when GNU parallel/rush is available) plus shellcheck bin/; C4 one evidence line per acceptance criterion",
        "        local mode: --branch delivery/<id> --body-file <file>; CI mode: reads GITHUB_* and gh pr view",
        f"  see:  {ADR16}",
    ),
    "backlog finish": (
        "clerk backlog finish — reconcile a submitted unit to done",
        "  runs: gh pr view --json state,mergedAt (merge detected via PR state, never ancestry); closes the unit; tears down the worktree; --watch wraps gh pr checks --watch",
        f"  see:  {ADR15}",
    ),
    "backlog return": (
        "clerk backlog return — send a unit back to discovery (verdict: cannot be fulfilled as designed)",
        '  runs: requires --reason "<text>"; renames delivery/<id> -> returned/<id> (local; pushes',
        "        the new ref and deletes delivery/<id> on origin when reachable) so the attempt",
        "        survives as grill evidence, then git worktree remove; bd update <id> --status open",
        '        --remove-label stage:ready --assignee ""                (backlog: bd)',
        "        gh issue reopen <id> + edit --remove-label ready-for-agent --remove-assignee (backlog: gh)",
        "        then files the reason verbatim as an impediment-typed capture referencing",
        "        returned/<id>: bd create --type impediment (backlog: bd) / gh issue create",
        "        --label type:impediment (backlog: gh); offline: local rename only, remote",
        "        deferred to sync; job-context refuses",
        f"  see:  {ADR16}",
    ),
}

for graph_verb in ("inbox children", "inbox frontier", "inbox blockers", "inbox blocked"):
    EXPLAIN_TEXT[graph_verb] = (
        f"clerk {graph_verb} — query inbox graph relationships as Clerk-owned JSON",
        "  usage: clerk inbox children|frontier|blockers|blocked <id> [--pretty]",
        "  runs: bd show <id> --readonly --json and normalizes parent-child / blocks edges",
        f"  see:  {ADR15}",
    )

for mutation_verb in (
    "inbox parent",
    "inbox dep",
    "inbox claim",
    "inbox release",
    "inbox note",
    "inbox update",
    "inbox resolve",
):
    EXPLAIN_TEXT[mutation_verb] = (
        f"clerk {mutation_verb} — mutate generic inbox graph/planning state",
        "  usage: clerk inbox parent set|clear ...; clerk inbox dep add|remove ...; clerk inbox claim|release <id>; clerk inbox note|update|resolve ...",
        "  runs: bd update / bd dep / bd close behind validated Clerk guards",
        f"  see:  {ADR15}",
    )


def roster_text() -> str:
    return "\n".join(ROSTER_LINES) + "\n"


def verb_label(path: Sequence[str]) -> str:
    return " ".join(path)


def all_public_verb_paths() -> set[tuple[str, ...]]:
    return {(verb,) for verb in TOP_LEVEL_VERBS} | {
        (noun, verb) for noun, verbs in NOUN_VERBS.items() for verb in verbs
    }


def iter_public_verb_labels() -> Iterable[str]:
    for verb in TOP_LEVEL_VERBS:
        yield verb
    for noun, verbs in NOUN_VERBS.items():
        for verb in verbs:
            yield f"{noun} {verb}"
