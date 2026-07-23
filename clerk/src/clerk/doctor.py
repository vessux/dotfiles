"""Python implementation of ``clerk doctor``."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

from . import __version__
from .manifest import ManifestStatus, read_manifest
from .output import Palette


def repo_root() -> Path | None:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if proc.returncode != 0:
        return None
    root = proc.stdout.rstrip("\n")
    return Path(root) if root else None


def _usage(message: str) -> int:
    print(message, file=sys.stderr)
    return 2


def _canon(path: str | Path) -> str:
    try:
        return str(Path(path).resolve(strict=False))
    except OSError:
        return str(path)


class DoctorReport:
    def __init__(self, palette: Palette) -> None:
        self.palette = palette
        self.failures = 0

    def ok(self, message: str) -> None:
        print(f"  {self.palette.green}[ ok ]{self.palette.reset} {message}")

    def warn(self, message: str) -> None:
        print(f"  {self.palette.yellow}[warn]{self.palette.reset} {message}")

    def fail(self, message: str) -> None:
        print(f"  {self.palette.red}[fail]{self.palette.reset} {message}")
        self.failures += 1

    def hint(self, message: str) -> None:
        print(f"         {message}")


def parse_args(argv: Sequence[str]) -> tuple[int, str] | int:
    fix = 0
    backend = ""
    args = list(argv)
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--fix":
            fix = 1
        elif arg == "--backend":
            if i + 1 >= len(args):
                return _usage("clerk doctor: --backend needs a value — use --backend bd or --backend gh")
            backend = args[i + 1]
            i += 1
        elif arg.startswith("--backend="):
            backend = arg[len("--backend=") :]
        else:
            return _usage(f"clerk doctor: unknown argument '{arg}' — usage: clerk doctor [--fix --backend bd|gh]")
        i += 1

    if fix:
        if backend in {"bd", "gh"}:
            return fix, backend
        if backend == "":
            return _usage("clerk doctor: --fix requires --backend bd|gh — rerun as 'clerk doctor --fix --backend bd' (or gh)")
        return _usage(f"clerk doctor: unknown backend '{backend}' — use --backend bd or --backend gh")
    if backend:
        return _usage("clerk doctor: --backend applies only with --fix — rerun with --fix, e.g. 'clerk doctor --fix --backend bd'")
    return fix, backend


def run_doctor(argv: Sequence[str], env: Mapping[str, str] = os.environ) -> int:
    parsed = parse_args(argv)
    if isinstance(parsed, int):
        return parsed
    fix, backend = parsed

    palette = Palette.from_env(env)
    report = DoctorReport(palette)
    root = repo_root()

    if root is not None:
        print(f"{palette.bold}clerk doctor{palette.reset} — {root}")
    else:
        print(f"{palette.bold}clerk doctor{palette.reset}")

    if root is None:
        report.fail(".clerk marker: not inside a git repository")
        report.hint("cd into the target repo, then rerun 'clerk doctor'")
    else:
        manifest_path = root / ".clerk"
        manifest = read_manifest(manifest_path)
        if manifest.status is ManifestStatus.OK:
            report.ok(f".clerk marker: backlog: {manifest.backend} ({manifest_path})")
        elif fix:
            try:
                manifest_path.write_text(f"backlog: {backend}\n", encoding="utf-8")
                manifest = read_manifest(manifest_path)
            except OSError:
                manifest = read_manifest(manifest_path)
            if manifest.status is ManifestStatus.OK:
                report.ok(f".clerk marker: provisioned backlog: {manifest.backend} ({manifest_path})")
                report.hint("commit .clerk so worktrees and clones see it: git add .clerk && git commit")
            else:
                report.fail(f".clerk marker: could not provision ({manifest_path})")
                report.hint(f"check that {root} is writable and .clerk is not a directory")
        elif manifest.status is ManifestStatus.MISSING:
            report.fail(f".clerk marker: missing ({manifest_path})")
            report.hint("provision it: clerk doctor --fix --backend bd   (or --backend gh)")
        else:
            report.fail(f".clerk marker: invalid ({manifest_path})")
            report.hint("expected a single line 'backlog: bd' or 'backlog: gh' (comments after # are fine)")
            report.hint("rewrite it: clerk doctor --fix --backend bd   (or --backend gh)")

    home = env.get("HOME", "")
    candidates = [Path(home) / ".config/bin/bd"]
    if root is not None:
        candidates.append(root / "bin/bd")

    resolved = shutil.which("bd", path=env.get("PATH"))
    shim = next((candidate for candidate in candidates if candidate.is_file() and os.access(candidate, os.X_OK)), None)
    if resolved is None:
        report.warn("bd shim: no 'bd' on PATH — bd-backed verbs will not work until one is installed")
    else:
        is_shim = any(_canon(resolved) == _canon(candidate) for candidate in candidates)
        if is_shim:
            report.ok(f"bd shim: {resolved} (shim wins PATH resolution)")
        elif shim is not None:
            report.fail(f"bd shim: SHADOWED — 'bd' resolves to {resolved}, expected shim {shim}")
            report.hint(f"fix: put {shim.parent} before {Path(resolved).parent} in PATH")
        else:
            report.warn("bd shim: 'bd' resolves to {resolved} and no clerk-managed shim exists (~/.config/bin/bd or <repo>/bin/bd)".format(resolved=resolved))

    report.ok(f"version: clerk {__version__} (clerk --version reports the same string)")

    if shutil.which("gh", path=env.get("PATH")) is None:
        report.warn("gh auth: gh not on PATH (non-fatal) — install gh before using gh-backed verbs")
    else:
        gh = subprocess.run(
            ["gh", "auth", "status"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=dict(env),
            check=False,
        )
        if gh.returncode == 0:
            report.ok("gh auth: authenticated")
        else:
            report.warn("gh auth: not authenticated (non-fatal) — run 'gh auth login' before gh-backed verbs")

    if report.failures == 0:
        print(f"{palette.green}clerk doctor: all clear{palette.reset}")
        return 0
    print(f"{palette.red}clerk doctor: {report.failures} problem(s) — fix the [fail] lines above{palette.reset}")
    return 1
