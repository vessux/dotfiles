"""Clerk Python switchboard entrypoint."""

from __future__ import annotations

import os
import sys
from collections.abc import Sequence

from .legacy import run_legacy
from .ownership import is_python_owned


def main(argv: Sequence[str] | None = None) -> int:
    """Dispatch public Clerk argv to Python-owned handlers or legacy fallback."""

    args = list(sys.argv[1:] if argv is None else argv)

    if os.environ.get("CLERK_FORCE_LEGACY") not in {None, "", "0"}:
        return run_legacy(args)

    if is_python_owned(args):
        # No verb paths are Python-owned in this slice. Keeping the branch explicit
        # makes accidental table/handler skew fail closed instead of falling into a
        # half-ported implementation silently.
        print(
            "clerk: Python-owned verb has no handler yet — set CLERK_FORCE_LEGACY=1 and run 'clerk doctor'",
            file=sys.stderr,
        )
        return 4

    return run_legacy(args)
