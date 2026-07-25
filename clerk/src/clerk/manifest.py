"""Strict parser for the Clerk repository manifest."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path


class ManifestStatus(Enum):
    OK = "ok"
    MISSING = "missing"
    INVALID = "invalid"
    AMBIGUOUS = "ambiguous"


@dataclass(frozen=True)
class ManifestResult:
    status: ManifestStatus
    path: Path
    backend: str | None = None
    project_gate: str | None = None

    @property
    def is_ok(self) -> bool:
        return self.status is ManifestStatus.OK


def _directive(line: str) -> str:
    line = line.split("#", 1)[0]
    return line.strip()


def parse_manifest(text: str, path: Path) -> ManifestResult:
    """Parse manifest content from *path* for both checkout and Git-tree reads."""

    directives = [directive for raw in text.splitlines() if (directive := _directive(raw))]
    backlog = [line[len("backlog:") :].strip() for line in directives if line.startswith("backlog:")]
    gates = [line[len("project-gate:") :].strip() for line in directives if line.startswith("project-gate:")]
    if len(backlog) != 1 or len(gates) > 1 or len(directives) != len(backlog) + len(gates):
        return ManifestResult(ManifestStatus.INVALID if not directives else ManifestStatus.AMBIGUOUS, path)
    backend = backlog[0]
    if backend not in {"bd", "gh"}:
        return ManifestResult(ManifestStatus.INVALID, path)
    return ManifestResult(ManifestStatus.OK, path, backend, gates[0] if gates else None)


def read_manifest(path: Path) -> ManifestResult:
    """Read and parse a v1 manifest from the working tree."""

    if not path.is_file():
        return ManifestResult(ManifestStatus.MISSING, path)
    try:
        return parse_manifest(path.read_text(encoding="utf-8"), path)
    except OSError:
        return ManifestResult(ManifestStatus.INVALID, path)
