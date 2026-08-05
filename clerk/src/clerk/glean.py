"""Transcript harvesting for ``clerk glean``."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from .commands import _bd_ensure_impediment_type
from .proc import CommandRunner
from .work_graph import BdWorkGraphAdapter, WorkGraphBackendError

_PROMPT = """You are a retrospective friction harvester (glean). You are reading a CHUNK of a Claude Code session transcript (JSONL lines) to find IMPEDIMENTS: friction the agent routed around that would recur and cost tokens unless an instruction, skill, or tool changes.

IMPEDIMENT DEFINITION (ADR 0012): friction the agent had to route around that *would recur and cost tokens again unless an instruction, skill, or tool changed*. A bare `is_error` from normal probing (empty grep, a guard that fails) is NOT an impediment; a denied permission, an interface retried three times, a misfiring bundled skill, or an ambiguous injected instruction IS.

Highest-value class: friction with *our own* instructions/skills — those we can actually fix.

For each impediment you find, output ONE JSON object on its own line with this exact shape:
{
  "type": "impediment",
  "title": "<one-line summary, <=80 chars>",
  "body": "<evidence-rich description: quote the failing command, the error, the retry count, roughly what it cost. Do NOT decide the fix — choosing which instruction to change is a grill decision, not a capture-time call.>",
  "transcript_file": "<path>",
  "chunk_lines": "<start>-<end>"
}

If you find no impediments, output exactly one JSON object:
{"type":"none","reason":"<why no recurring workflow/tooling friction was found>"}

Malformed output is treated as a failed harvest and the watermark will not advance.

Categories (ADR 0016 loop map) — this run only emits `type: impediment`. Future categories: `criteria-miss`, `sort-miss`, `prep-miss`.

"""


class GleanFailure(Exception):
    pass


def _state_dir(env: Mapping[str, str]) -> Path:
    configured = env.get("CLERK_GLEAN_STATE_DIR")
    if configured:
        return Path(configured)
    return Path(env.get("HOME") or "/") / ".local" / "state" / "clerk"


def _transcript_dirs(root: Path, env: Mapping[str, str]) -> tuple[Path, ...]:
    configured = env.get("CLERK_GLEAN_TRANSCRIPT_DIR")
    if configured:
        return (Path(configured),)
    projects = Path(env.get("CLERK_GLEAN_PROJECTS_ROOT") or Path(env.get("HOME") or "/") / ".config" / "claude-code" / "projects")
    slug = str(root.resolve()).replace("/", "-")
    return (projects / slug,)


def _watermark_path(state_dir: Path, transcript: Path) -> Path:
    digest = hashlib.sha256(str(transcript.resolve()).encode()).hexdigest()
    return state_dir / f"{digest}.watermark"


def _read_watermark(state_dir: Path, transcript: Path) -> int:
    path = _watermark_path(state_dir, transcript)
    if not path.is_file():
        return 0
    try:
        return int(path.read_text() or "0")
    except (OSError, ValueError) as exc:
        raise GleanFailure(f"invalid watermark for {transcript}") from exc


def _write_watermark(state_dir: Path, transcript: Path, offset: int) -> None:
    path = _watermark_path(state_dir, transcript)
    temporary = ""
    try:
        with tempfile.NamedTemporaryFile("w", dir=state_dir, prefix=f"{path.name}.tmp.", delete=False) as handle:
            temporary = handle.name
            handle.write(str(offset))
        os.replace(temporary, path)
    except OSError as exc:
        if temporary:
            Path(temporary).unlink(missing_ok=True)
        raise GleanFailure(f"failed to write watermark for {transcript}") from exc


def _judgment_prompt(chunk: str, transcript: Path, start: int, end: int) -> str:
    return f"{_PROMPT}TRANSCRIPT CHUNK (lines {start}-{end} of {transcript}):\n{chunk}"


def _run_judgment(prompt: str, env: Mapping[str, str], runner: CommandRunner) -> str:
    command = env.get("CLERK_GLEAN_JUDGMENT_CMD")
    if command:
        result = runner.run(["bash", "-c", command], env=env, input=prompt)
    elif shutil.which("claude", path=env.get("PATH")):
        result = runner.run(
            [
                "claude",
                "-p",
                "--model",
                env.get("CLERK_GLEAN_MODEL", "haiku"),
                "--max-budget-usd",
                env.get("CLERK_GLEAN_MAX_BUDGET_USD", "0.05"),
            ],
            env=env,
            input=prompt,
        )
    else:
        print("clerk glean: no judgment runner available (expected claude on PATH)", file=sys.stderr)
        raise GleanFailure("no judgment runner")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise GleanFailure("judgment fork failed")
    if not result.stdout.strip():
        print("clerk glean: judgment fork produced no JSONL; watermark not advanced", file=sys.stderr)
        raise GleanFailure("empty judgment")
    return result.stdout


def _candidates(output: str) -> list[tuple[str, dict[str, Any]]]:
    candidates: list[tuple[str, dict[str, Any]]] = []
    seen_none = False
    for line in output.splitlines():
        if not line.strip():
            continue
        try:
            candidate = json.loads(line)
        except json.JSONDecodeError as exc:
            print("clerk glean: malformed judgment JSONL; watermark not advanced", file=sys.stderr)
            raise GleanFailure("malformed judgment") from exc
        if not isinstance(candidate, dict) or candidate.get("type") not in {"none", "impediment"}:
            print("clerk glean: malformed judgment JSONL; watermark not advanced", file=sys.stderr)
            raise GleanFailure("malformed judgment")
        if candidate["type"] == "none":
            seen_none = True
            continue
        if not candidate.get("title") or not candidate.get("body"):
            print("clerk glean: impediment candidate missing title/body; watermark not advanced", file=sys.stderr)
            raise GleanFailure("incomplete impediment")
        candidates.append((line, candidate))
    if seen_none and candidates:
        print("clerk glean: ambiguous judgment output; watermark not advanced", file=sys.stderr)
        raise GleanFailure("ambiguous judgment")
    if seen_none:
        return []
    if not candidates:
        print("clerk glean: ambiguous judgment output; watermark not advanced", file=sys.stderr)
        raise GleanFailure("ambiguous judgment")
    return candidates


def _existing_capture(backend: str, source_key: str, runner: CommandRunner) -> str:
    if backend == "bd":
        try:
            work = BdWorkGraphAdapter(runner).find_by_description(source_key)
        except WorkGraphBackendError as exc:
            print("clerk glean: capture lookup failed — rerun 'clerk glean' after the backend recovers", file=sys.stderr)
            raise GleanFailure("capture lookup failed") from exc
        return work.id if work is not None else ""
    result = runner.run(["gh", "issue", "list", "--search", source_key, "--json", "url", "--jq", ".[0].url // empty"])
    if result.returncode != 0:
        print("clerk glean: capture lookup failed — rerun 'clerk glean' after the backend recovers", file=sys.stderr)
        raise GleanFailure("capture lookup failed")
    return result.stdout.strip()


def _file_capture(backend: str, title: str, body: str, source_keys: Sequence[str], runner: CommandRunner) -> str:
    for source_key in source_keys:
        existing = _existing_capture(backend, source_key, runner)
        if existing:
            return existing
    temporary = ""
    try:
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            temporary = handle.name
            handle.write(body + "\n\n" + "\n".join(source_keys) + "\n")
        if backend == "bd":
            _bd_ensure_impediment_type(runner)
            adapter = BdWorkGraphAdapter(runner)
            result = adapter.create_impediment_from_file(title, temporary)
            if result.returncode != 0:
                raise GleanFailure("capture filing failed")
            id_ = result.stdout.strip()
            try:
                seen = adapter.find(id_)
            except WorkGraphBackendError as exc:
                raise GleanFailure("capture confirmation failed") from exc
            if seen is None or seen.id != id_:
                raise GleanFailure("capture confirmation failed")
            return id_
        if backend == "gh":
            result = runner.run(["gh", "issue", "create", "--title", title, "--body-file", temporary, "--label", "type:impediment"])
            if result.returncode != 0:
                raise GleanFailure("capture filing failed")
            url = result.stdout.strip()
            confirmed = runner.run(["gh", "issue", "view", url, "--json", "url", "--jq", ".url"])
            if confirmed.returncode != 0 or confirmed.stdout.strip() != url:
                raise GleanFailure("capture confirmation failed")
            return url
        raise GleanFailure(f"unsupported backend {backend}")
    finally:
        if temporary:
            Path(temporary).unlink(missing_ok=True)


def _judge_and_file(
    backend: str,
    transcript: Path,
    chunk: str,
    start: int,
    end: int,
    env: Mapping[str, str],
    runner: CommandRunner,
) -> str:
    output = _run_judgment(_judgment_prompt(chunk, transcript, start, end), env, runner)
    filed: list[str] = []
    for index, (raw, candidate) in enumerate(_candidates(output), start=1):
        stable_input = f"{transcript.resolve()}:{start}-{end}:{index}"
        legacy_input = f"{raw}\n{transcript}:{start}-{end}"
        source_keys = (
            f"glean-source-v2:{hashlib.sha256(stable_input.encode()).hexdigest()}",
            f"glean-source:{hashlib.sha256(legacy_input.encode()).hexdigest()}",
        )
        filed.append(_file_capture(backend, str(candidate["title"]), str(candidate["body"]), source_keys, runner))
    return "\n".join(filed)


def _process_transcript(
    backend: str,
    transcript: Path,
    state_dir: Path,
    minimum: int,
    env: Mapping[str, str],
    runner: CommandRunner,
) -> None:
    if not transcript.is_file() or transcript.stat().st_size == 0:
        return
    lines = transcript.read_text().splitlines()
    watermark = _read_watermark(state_dir, transcript)
    if watermark >= len(lines):
        return
    start = watermark + 1
    while start + minimum - 1 <= len(lines):
        end = start + minimum - 1
        chunk = "\n".join(lines[start - 1 : end]) + "\n"
        try:
            capture_ids = _judge_and_file(backend, transcript, chunk, start, end, env, runner)
        except GleanFailure as exc:
            print(f"glean: judgment fork failed for {transcript} lines {start}-{end}; watermark not advanced", file=sys.stderr)
            raise exc
        if capture_ids:
            print(f"  filed {capture_ids} (lines {start}-{end})")
        else:
            print(f"  judgment fork returned no capture for lines {start}-{end}")
        _write_watermark(state_dir, transcript, end)
        start = end + 1
    remaining = len(lines) - start + 1
    if 0 < remaining < minimum:
        print(f"glean: sub-threshold chunk skipped ({remaining} lines, min {minimum}) in {transcript}")


def _start_async(root: Path, state_dir: Path, env: Mapping[str, str]) -> int:
    log_path = state_dir / "glean.log"
    with log_path.open("a") as log:
        subprocess.Popen(
            [sys.executable, "-m", "clerk", "glean"],
            cwd=root,
            env=dict(env),
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    print(f"glean: async harvest started (log: {log_path})")
    return 0


def run_glean(
    backend: str,
    root: Path,
    argv: Sequence[str],
    env: Mapping[str, str] = os.environ,
    runner: CommandRunner | None = None,
) -> int:
    """Run the Python-owned Glean watermark sweep."""

    async_ = False
    for arg in argv:
        if arg == "--async":
            async_ = True
        else:
            print(f"clerk glean: unknown argument '{arg}' — usage: clerk glean [--async]", file=sys.stderr)
            return 2

    state_dir = _state_dir(env)
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        if async_:
            return _start_async(root, state_dir, env)
        lock = (state_dir / "glean.lock").open("a+")
    except OSError:
        print(f"clerk glean: state path unavailable at {state_dir} — fix it, then rerun 'clerk glean'", file=sys.stderr)
        return 5

    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("glean: another instance is running — exiting", file=sys.stderr)
            return 0

        directories = _transcript_dirs(root, env)
        transcripts = sorted(path for directory in directories if directory.is_dir() for path in directory.rglob("*.jsonl") if path.is_file())
        display = " ".join(str(path) for path in directories)
        if not transcripts:
            print(f"glean: no transcript files found in {display}")
            return 0

        print(f"glean: scanning {len(transcripts)} transcript file(s)")
        command_runner = runner or CommandRunner()
        minimum = int(env.get("CLERK_GLEAN_MIN_CHUNK_LINES", "50"))
        failed = False
        for transcript in transcripts:
            print(f"  harvesting {transcript}")
            try:
                _process_transcript(backend, transcript, state_dir, minimum, env, command_runner)
            except (GleanFailure, OSError):
                failed = True
                print(f"glean: failed to process {transcript}", file=sys.stderr)
        if failed:
            print("glean: harvest completed with failures — rerun 'clerk glean'; failed watermarks were not advanced", file=sys.stderr)
            return 5
        print("glean: harvest complete")
        return 0
    finally:
        lock.close()
