"""Static migration ownership for public Clerk verb paths.

The first Python rewrite slice owns no workflow verbs yet. Keeping the table explicit
means later slices move a verb by changing one public switchboard, while every
unowned path falls through to the preserved shell implementation.
"""

from __future__ import annotations

from collections.abc import Sequence

# Public verb paths currently implemented in Python. Empty by design for the
# project-shell slice: compatibility is provided by legacy fallback.
PYTHON_OWNED_VERBS: frozenset[tuple[str, ...]] = frozenset()

_TOP_LEVEL_VERBS = {"capture", "sync", "doctor", "glean"}
_NOUN_VERBS = {
    "inbox": {
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
    },
    "backlog": {
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
    },
}


def public_verb_path(argv: Sequence[str]) -> tuple[str, ...] | None:
    """Return the public Clerk verb path in *argv*, if it is a roster path.

    This parser is intentionally narrow: it identifies ownership only. Grammar,
    validation, help, marker gates, and all user-visible output stay with the
    implementation that owns the path; today that is always the legacy fallback.
    """

    args = list(argv)
    if not args:
        return None
    if args[0] == "--explain":
        args = args[1:]
        if not args:
            return None
    if args[0] in {"--version", "-V", "--help", "-h"}:
        return (args[0],)
    if args[0] in _TOP_LEVEL_VERBS:
        return (args[0],)
    if len(args) >= 2 and args[0] in _NOUN_VERBS and args[1] in _NOUN_VERBS[args[0]]:
        return (args[0], args[1])
    return None


def is_python_owned(argv: Sequence[str]) -> bool:
    """Whether the supplied public argv should run in Python."""

    path = public_verb_path(argv)
    return path in PYTHON_OWNED_VERBS if path is not None else False
