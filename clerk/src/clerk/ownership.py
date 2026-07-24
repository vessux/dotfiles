"""Static migration ownership for public Clerk verb paths.

This slice moves Clerk's command-boundary diagnostics, read-only item query
windows, Capture/text-based Inbox mutations, and Planning graph mutations to
Python while leaving delivery workflow verb bodies on the legacy shell fallback.
Ownership is therefore split: Python owns global help/explain/version, manifest gating,
doctor, and the explicit command tables; unported workflow mutations are exec'd
into the fallback after the Python gate accepts them.
"""

from __future__ import annotations

from collections.abc import Sequence

from .commands import MUTATION_HANDLERS, QUERY_HANDLERS
from .roster import NOUN_VERBS, TOP_LEVEL_VERBS

PYTHON_OWNED_DIRECT_PATHS: frozenset[tuple[str, ...]] = frozenset(
    {("doctor",), ("--version",), ("-V",), ("--help",), ("-h",)} | set(QUERY_HANDLERS) | set(MUTATION_HANDLERS)
)


def public_verb_path(argv: Sequence[str]) -> tuple[str, ...] | None:
    """Return the public Clerk verb path in *argv*, if it is a roster path."""

    args = list(argv)
    if not args:
        return None
    if args[0] == "--explain":
        args = args[1:]
        if not args:
            return None
    if args[0] in {"--version", "-V", "--help", "-h"}:
        return (args[0],)
    if args[0] in TOP_LEVEL_VERBS:
        return (args[0],)
    if len(args) >= 2 and args[0] in NOUN_VERBS and args[1] in NOUN_VERBS[args[0]]:
        return (args[0], args[1])
    return None


def is_python_owned(argv: Sequence[str]) -> bool:
    """Whether the supplied public argv should be handled by Python."""

    args = list(argv)
    if not args:
        return True
    if "--explain" in args or "--help" in args or "-h" in args:
        return True
    path = public_verb_path(args)
    return path in PYTHON_OWNED_DIRECT_PATHS if path is not None else True
