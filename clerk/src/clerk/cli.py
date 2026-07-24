"""Clerk Python switchboard entrypoint."""

from __future__ import annotations

import os
import sys
from collections.abc import Sequence
from pathlib import Path

from . import __version__
from .commands import ClerkExit, MUTATION_HANDLERS, QUERY_HANDLERS, run_mutation, run_query
from .doctor import repo_root, run_doctor
from .legacy import run_legacy
from .manifest import ManifestStatus, read_manifest
from .proc import CommandRunner
from .project_gate import cmd_backlog_gate, cmd_backlog_submit
from .roster import EXPLAIN_TEXT, NOUN_VERBS, ROSTER_LINES, TOP_LEVEL_VERBS, roster_text, verb_label

# The Python core owns diagnostics, help/explain/version, manifest gating,
# doctor, read-only item query windows, Capture/text-based Inbox mutations,
# Planning graph mutations/claims, and the Inbox ready/drop bridge.
# Unported workflow verb bodies remain on the shell fallback for this slice.
PYTHON_QUERY_VERBS: frozenset[tuple[str, ...]] = frozenset(QUERY_HANDLERS)
PYTHON_MUTATION_VERBS: frozenset[tuple[str, ...]] = frozenset(MUTATION_HANDLERS)
PYTHON_PROJECT_GATE_VERBS: frozenset[tuple[str, ...]] = frozenset({("backlog", "submit"), ("backlog", "gate")})

LEGACY_WORKFLOW_VERBS: frozenset[tuple[str, ...]] = frozenset(
    ({("capture",), ("sync",), ("glean",)} | {(noun, verb) for noun, verbs in NOUN_VERBS.items() for verb in verbs})
    - PYTHON_QUERY_VERBS
    - PYTHON_MUTATION_VERBS
    - PYTHON_PROJECT_GATE_VERBS
)

# Kept explicit for the legacy public contract: unknown verbs are exit 2 with
# roster; known-but-unimplemented verbs are exit 3 without roster. There are no
# such stubs in this migration slice, but the distinction remains one table away.
PYTHON_STUB_VERBS: frozenset[tuple[str, ...]] = frozenset()


def _print_roster(*, stream) -> None:
    stream.write(roster_text())


def _usage(message: str) -> int:
    print(message, file=sys.stderr)
    return 2


def _unknown(label: str) -> int:
    print(f"clerk: unknown verb '{label}'", file=sys.stderr)
    _print_roster(stream=sys.stderr)
    return 2


def _not_implemented(path: tuple[str, ...]) -> int:
    print(
        f"clerk: '{verb_label(path)}' is not yet implemented in this generation (see dotfiles-dft epic)",
        file=sys.stderr,
    )
    return 3


def _split_control_flags(argv: Sequence[str]) -> tuple[list[str], bool, bool]:
    explain = False
    help_ = False
    args: list[str] = []
    for arg in argv:
        if arg == "--explain":
            explain = True
        elif arg in {"--help", "-h"}:
            help_ = True
        else:
            args.append(arg)
    return args, explain, help_


def _parse_verb(args: Sequence[str]) -> tuple[tuple[str, ...] | None, list[str], int | None]:
    if not args:
        return None, [], None

    first = args[0]
    if first in TOP_LEVEL_VERBS:
        return (first,), list(args[1:]), None

    if first in NOUN_VERBS:
        if len(args) == 1:
            print(f"clerk: '{first}' needs a verb", file=sys.stderr)
            _print_roster(stream=sys.stderr)
            return None, [], 2
        subverb = args[1]
        if subverb not in NOUN_VERBS[first]:
            return None, [], _unknown(" ".join(args))
        return (first, subverb), list(args[2:]), None

    return None, [], _unknown(first)


def _explain(path: tuple[str, ...]) -> int:
    text = EXPLAIN_TEXT.get(verb_label(path))
    if text is None:
        return _unknown(verb_label(path))
    print("\n".join(text))
    return 0


def _manifest_context(path: tuple[str, ...]) -> tuple[Path, str] | int:
    # The delivery gate is intentionally backend-marker-free so CI can run it in
    # checkout states that precede Clerk cutover.
    if path == ("backlog", "gate"):
        root = repo_root()
        if root is None:
            print(
                "clerk: not inside a git repository — cd into the target repo, then rerun 'clerk backlog gate'",
                file=sys.stderr,
            )
            return 4
        return root, ""

    root = repo_root()
    if root is None:
        print(
            "clerk: not inside a git repository — cd into the target repo, then run 'clerk doctor'",
            file=sys.stderr,
        )
        return 4

    manifest_path = root / ".clerk"
    manifest = read_manifest(manifest_path)
    if manifest.status is ManifestStatus.OK:
        assert manifest.backend is not None
        return root, manifest.backend
    if manifest.status is ManifestStatus.MISSING:
        print(f"clerk: missing .clerk marker at {manifest_path} — run 'clerk doctor' to provision it", file=sys.stderr)
        return 4
    print(f"clerk: invalid .clerk marker at {manifest_path} — run 'clerk doctor' to diagnose it", file=sys.stderr)
    return 4


def _manifest_gate(path: tuple[str, ...]) -> int | None:
    context = _manifest_context(path)
    if isinstance(context, int):
        return context
    return None


def main(argv: Sequence[str] | None = None) -> int:
    """Dispatch public Clerk argv to Python-owned handlers or legacy fallback."""

    original_args = list(sys.argv[1:] if argv is None else argv)

    if os.environ.get("CLERK_FORCE_LEGACY") not in {None, "", "0"}:
        return run_legacy(original_args)

    args, explain, help_ = _split_control_flags(original_args)

    if not args:
        if explain:
            return _usage("clerk: --explain needs a verb — e.g. 'clerk --explain backlog claim'")
        if help_:
            print(f"clerk {__version__} — workflow verb facade (ADR 0015)")
            for line in ROSTER_LINES:
                print(line)
            return 0
        print("clerk: missing verb", file=sys.stderr)
        _print_roster(stream=sys.stderr)
        return 2

    if args[0] in {"--version", "-V"}:
        print(f"clerk {__version__}")
        return 0

    path, remaining, parse_exit = _parse_verb(args)
    if parse_exit is not None:
        return parse_exit
    if path is None:
        return _usage("clerk: missing verb")

    if explain or help_:
        return _explain(path)

    if path == ("doctor",):
        return run_doctor(remaining)

    if path in PYTHON_STUB_VERBS:
        return _not_implemented(path)

    if path in PYTHON_QUERY_VERBS:
        context = _manifest_context(path)
        if isinstance(context, int):
            return context
        root, backend = context
        return run_query(path, backend, root, remaining)

    if path in PYTHON_MUTATION_VERBS:
        context = _manifest_context(path)
        if isinstance(context, int):
            return context
        root, backend = context
        return run_mutation(path, backend, root, remaining)

    if path in PYTHON_PROJECT_GATE_VERBS:
        context = _manifest_context(path)
        if isinstance(context, int):
            return context
        root, backend = context
        try:
            handler = cmd_backlog_submit if path == ("backlog", "submit") else cmd_backlog_gate
            return handler(backend, root, remaining, CommandRunner(), os.environ)
        except ClerkExit as exc:
            return exc.code

    if path in LEGACY_WORKFLOW_VERBS:
        refused = _manifest_gate(path)
        if refused is not None:
            return refused
        return run_legacy(original_args)

    return _unknown(verb_label(path))
