#!/usr/bin/env python3
"""Tests for extract.py — the deterministic glean candidate extractor.

Self-contained: builds a fixture session tree (a main transcript + one subagent
transcript with its .meta.json sidecar) encoding the exact markers found in real
Claude Code JSONL, then asserts what extract.py distils. Run: python3 test_extract.py

The fixture pins the two build-time unknowns the design flagged:
  - the permission-DENIAL marker (auto-mode classifier + native user rejection)
  - the retry-similarity heuristic (same tool + near-identical input, per session)
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXTRACT = HERE / "extract.py"

UUID = "11111111-2222-3333-4444-555555555555"
SUB_ID = "agent-deadbeefcafe0001"


def _line(role, blocks, ts):
    return json.dumps({"timestamp": ts, "message": {"role": role, "content": blocks}})


def _tool_use(tid, name, inp):
    return {"type": "tool_use", "id": tid, "name": name, "input": inp}


def _tool_result(tid, text, is_error):
    return {"type": "tool_result", "tool_use_id": tid, "content": text, "is_error": is_error}


def build_fixture(root: Path) -> str:
    """Create projects/<slug>/<uuid>.jsonl + subagents tree. Returns projects dir."""
    projects = root / "projects"
    slug = projects / "-some-repo--worktrees-branch"   # a worktree slug, on purpose
    subs = slug / UUID / "subagents"
    subs.mkdir(parents=True)

    main = slug / f"{UUID}.jsonl"
    ts = "2026-06-27T10:00:0{}Z"
    lines = []

    # 1. permission denial (auto-mode classifier) on a git push — IMPEDIMENT
    lines.append(_line("assistant", [_tool_use("toolu_push", "Bash",
                  {"command": "git push origin main"})], ts.format(0)))
    lines.append(_line("user", [_tool_result("toolu_push",
                  "Permission for this action was denied by the Claude Code auto mode "
                  "classifier. Reason: Pushes directly to origin main bypassing PR review.",
                  True)], ts.format(1)))

    # 2. worktree-teardown <tool_use_error> — the paradigm recurring IMPEDIMENT (iv6)
    lines.append(_line("assistant", [_tool_use("toolu_wt", "ExitWorktree",
                  {"action": "remove"})], ts.format(2)))
    lines.append(_line("user", [_tool_result("toolu_wt",
                  "<tool_use_error>Worktree has 2 commits on worktree-x. Removing will "
                  "discard this work permanently. Confirm with the user.</tool_use_error>",
                  True)], ts.format(3)))

    # 3. native user rejection — IMPEDIMENT (a denial encoding)
    lines.append(_line("assistant", [_tool_use("toolu_rej", "Bash",
                  {"command": "rm -rf build/"})], ts.format(4)))
    lines.append(_line("user", [_tool_result("toolu_rej",
                  "The user doesn't want to proceed with this tool use. The tool use "
                  "was rejected (eg. if it was a file edit).", True)], ts.format(5)))

    # 4. a normal-probing error (empty-ish failure) — still a candidate; fork filters it
    lines.append(_line("assistant", [_tool_use("toolu_grep", "Bash",
                  {"command": "grep -r needle src/"})], ts.format(6)))
    lines.append(_line("user", [_tool_result("toolu_grep", "Exit code 1 ", True)],
                  ts.format(7)))

    # 5. a retried command: same Bash issued 3x, erroring each time -> retry_count=3
    for i, tid in enumerate(("toolu_r1", "toolu_r2", "toolu_r3")):
        lines.append(_line("assistant", [_tool_use(tid, "Bash",
                      {"command": "bd dolt push   # extra   spaces"})], ts.format(0)))
        lines.append(_line("user", [_tool_result(tid,
                      "<tool_use_error>dolt: remote rejected</tool_use_error>", True)],
                      ts.format(1)))

    # 6. a NON-error tool_result — must NOT become a candidate
    lines.append(_line("assistant", [_tool_use("toolu_ok", "Read",
                  {"file_path": "/x/y.md"})], ts.format(2)))
    lines.append(_line("user", [_tool_result("toolu_ok", "file contents...", False)],
                  ts.format(3)))

    main.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # subagent transcript: one error, attributed via meta.json
    sub = subs / f"{SUB_ID}.jsonl"
    sub_lines = [
        _line("assistant", [_tool_use("toolu_sub", "Edit",
              {"file_path": "/x/z.md", "old_string": "a", "new_string": "b"})], ts.format(0)),
        _line("user", [_tool_result("toolu_sub",
              "<tool_use_error>File has not been read yet. Read it first before "
              "writing to it.</tool_use_error>", True)], ts.format(1)),
    ]
    sub.write_text("\n".join(sub_lines) + "\n", encoding="utf-8")
    (subs / f"{SUB_ID}.meta.json").write_text(json.dumps(
        {"agentType": "general-purpose", "description": "Refactor the widget",
         "toolUseId": "toolu_parenttask"}), encoding="utf-8")

    return str(projects)


def run_extract(projects: str):
    out = subprocess.run(
        [sys.executable, str(EXTRACT), "--uuid", UUID, "--projects-dir", projects],
        capture_output=True, text=True)
    assert out.returncode == 0, f"extract.py failed:\n{out.stderr}"
    return json.loads(out.stdout)


def main() -> int:
    assert EXTRACT.exists(), f"extract.py not found at {EXTRACT} (RED expected before impl)"
    with tempfile.TemporaryDirectory() as td:
        projects = build_fixture(Path(td))
        report = run_extract(projects)

    cands = report["candidates"]
    by_tid = {}
    for c in cands:
        by_tid.setdefault(c["tool_use_id"], c)

    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # discovery found main + the subagent
    check(report["summary"]["files_scanned"] == 2,
          f"expected 2 files scanned, got {report['summary'].get('files_scanned')}")

    # the non-error result is excluded
    check("toolu_ok" not in by_tid, "non-error tool_result leaked into candidates")

    # 7 errors total -> but the 3 retries collapse? No: each error is a candidate.
    # main errors: push, wt, rej, grep, r1, r2, r3 (7) + sub (1) = 8
    check(len(cands) == 8, f"expected 8 candidates, got {len(cands)}")

    # permission denial: classified + Reason extracted + command joined
    push = by_tid.get("toolu_push", {})
    check(push.get("error_class") == "permission_denied",
          f"push not classified permission_denied: {push.get('error_class')}")
    check("PR review" in (push.get("denial_reason") or ""),
          f"push denial_reason not extracted: {push.get('denial_reason')!r}")
    check(push.get("tool") == "Bash" and "git push" in (push.get("command") or ""),
          f"push command not joined: {push.get('command')!r}")

    # worktree-teardown: <tool_use_error> stripped from excerpt
    wt = by_tid.get("toolu_wt", {})
    check(wt.get("error_class") == "tool_error",
          f"wt not tool_error: {wt.get('error_class')}")
    check("<tool_use_error>" not in (wt.get("error_excerpt") or ""),
          "tool_use_error wrapper not stripped")
    check("discard this work permanently" in (wt.get("error_excerpt") or ""),
          f"wt excerpt missing: {wt.get('error_excerpt')!r}")

    # native rejection
    rej = by_tid.get("toolu_rej", {})
    check(rej.get("error_class") == "user_rejected",
          f"rej not user_rejected: {rej.get('error_class')}")

    # normal probe still present, classified runtime_error (fork will filter it out)
    grep = by_tid.get("toolu_grep", {})
    check(grep.get("error_class") == "runtime_error",
          f"grep not runtime_error: {grep.get('error_class')}")

    # retry detection: the 3 identical bd dolt push errors each carry retry_count=3
    r1 = by_tid.get("toolu_r1", {})
    check(r1.get("retry_count") == 3,
          f"retry_count expected 3, got {r1.get('retry_count')}")

    # subagent attribution via meta.json
    sub = by_tid.get("toolu_sub", {})
    check(sub.get("source") == "subagent", f"sub source wrong: {sub.get('source')}")
    check(sub.get("agent_type") == "general-purpose",
          f"sub agent_type wrong: {sub.get('agent_type')}")
    check("Refactor the widget" == (sub.get("agent_description") or ""),
          f"sub description wrong: {sub.get('agent_description')!r}")

    # main-thread candidates are marked source=main
    check(push.get("source") == "main", f"push source wrong: {push.get('source')}")

    if failures:
        print("FAIL:")
        for f in failures:
            print("  -", f)
        return 1
    print(f"OK — {len(cands)} candidates extracted, all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
