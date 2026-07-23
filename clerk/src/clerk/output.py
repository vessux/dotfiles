"""Output helpers for Clerk's public CLI contract."""

from __future__ import annotations

import os
import sys
from collections.abc import Mapping
from dataclasses import dataclass


@dataclass(frozen=True)
class Palette:
    bold: str = ""
    red: str = ""
    green: str = ""
    yellow: str = ""
    reset: str = ""

    @classmethod
    def from_env(cls, env: Mapping[str, str] = os.environ) -> "Palette":
        if "NO_COLOR" in env:
            enabled = False
        elif env.get("CLICOLOR_FORCE") not in {None, "", "0"}:
            enabled = True
        else:
            enabled = sys.stdout.isatty()

        if not enabled:
            return cls()
        return cls(
            bold="\033[1m",
            red="\033[31m",
            green="\033[32m",
            yellow="\033[33m",
            reset="\033[0m",
        )
