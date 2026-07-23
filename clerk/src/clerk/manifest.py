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

    @property
    def is_ok(self) -> bool:
        return self.status is ManifestStatus.OK


def _directive(line: str) -> str:
    line = line.split("#", 1)[0]
    return line.strip()


def read_manifest(path: Path) -> ManifestResult:
    """Parse manifest v0 from *path*.

    Valid v0 is exactly one non-comment directive: ``backlog: bd`` or
    ``backlog: gh``. Surrounding whitespace and trailing comments are accepted.
    Missing files are reported separately from present-but-invalid manifests;
    multiple directive lines are ambiguous, which callers present with the same
    public invalid-marker diagnostic used by the legacy shell contract.
    """

    if not path.is_file():
        return ManifestResult(ManifestStatus.MISSING, path)

    directives: list[str] = []
    try:
        with path.open("r", encoding="utf-8") as handle:
            for raw in handle:
                directive = _directive(raw)
                if directive:
                    directives.append(directive)
    except OSError:
        return ManifestResult(ManifestStatus.INVALID, path)

    if len(directives) != 1:
        return ManifestResult(ManifestStatus.INVALID if not directives else ManifestStatus.AMBIGUOUS, path)

    directive = directives[0]
    if not directive.startswith("backlog:"):
        return ManifestResult(ManifestStatus.INVALID, path)
    backend = directive[len("backlog:") :].strip()
    if backend not in {"bd", "gh"}:
        return ManifestResult(ManifestStatus.INVALID, path)
    return ManifestResult(ManifestStatus.OK, path, backend)
