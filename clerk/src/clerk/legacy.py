"""Legacy shell fallback for unported Clerk verb paths."""

from __future__ import annotations

import os
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path


def legacy_path(env: Mapping[str, str] = os.environ) -> Path:
    """Return the preserved shell implementation path supplied by the launcher."""

    configured = env.get("CLERK_LEGACY_PATH")
    if configured:
        return Path(configured)

    repo_root = env.get("CLERK_REPO_ROOT")
    if repo_root:
        return Path(repo_root) / "clerk" / "legacy" / "clerk.bash"

    # Developer fallback for `PYTHONPATH=clerk/src python -m clerk` from a checkout.
    return Path(__file__).resolve().parents[2] / "legacy" / "clerk.bash"


def run_legacy(argv: Sequence[str], env: Mapping[str, str] = os.environ) -> int:
    """Replace this process with the shell Clerk implementation."""

    path = legacy_path(env)
    if not path.exists():
        print(
            f"clerk: legacy implementation not found at {path} — run 'clerk doctor' from the dotfiles checkout",
            file=sys.stderr,
        )
        return 4

    process_env = dict(os.environ)
    os.execve(str(path), [str(path), *argv], process_env)
    raise AssertionError("os.execve returned unexpectedly")
