"""Subprocess seam for Clerk backend adapters."""

from __future__ import annotations

import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


class CommandRunner:
    """Small wrapper around subprocess.run, injectable in tests."""

    def run(
        self,
        args: Sequence[str],
        *,
        cwd: str | Path | None = None,
        env: Mapping[str, str] | None = None,
        input: str | None = None,
        timeout: float | None = None,
    ) -> CommandResult:
        try:
            proc = subprocess.run(
                list(args),
                cwd=str(cwd) if cwd is not None else None,
                env=dict(env) if env is not None else None,
                input=input,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=timeout,
            )
        except FileNotFoundError as exc:
            return CommandResult(tuple(args), 127, "", str(exc))
        except subprocess.TimeoutExpired as exc:
            return CommandResult(tuple(args), 124, exc.stdout or "", exc.stderr or "")
        return CommandResult(tuple(args), proc.returncode, proc.stdout, proc.stderr)
