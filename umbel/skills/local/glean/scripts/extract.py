#!/usr/bin/env python3
"""glean: distil one session's transcripts into a compact impediment-candidate list.

The session is the *main thread plus every subagent*. Subagent transcripts are
separate files at ``<slug>/<uuid>/subagents/agent-<id>.jsonl`` with an
``agent-<id>.meta.json`` sidecar ({agentType, description, toolUseId}); friction
concentrates there on delivery. We locate the whole set by **UUID discovery** (not
by constructing a slug — a worktree session lives under its own ``…--worktrees-<branch>``
slug), stream every file, and emit one candidate per ``is_error`` tool_result:

  - JOIN each error to the command that caused it via ``tool_use_id`` -> the assistant
    ``tool_use`` record (the error text alone does not carry the command).
  - CLASSIFY the error (permission_denied / user_rejected / tool_error / runtime_error)
    and, for permission denials, pull out the auto-mode classifier's *Reason*.
  - COUNT retries: how many times the same tool + near-identical input ran this session.
  - ATTRIBUTE subagent errors to their agent via the ``.meta.json`` sidecar.

Deterministic parse in code (cheap, testable, keeps megabytes of JSONL out of the
fork's context); the *judgment* — the fixability test, naming a remediation, filing
beads — is the fork's job. The output is JSON: {"summary": {...}, "candidates": [...]}.

stdlib only. Run ``extract.py --help``.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple

# --- error classification markers (pinned against real Claude Code transcripts) ---
PERMISSION_MARKER = "denied by the Claude Code auto mode classifier"
REJECTION_MARKERS = ("doesn't want to proceed", "the tool use was rejected")
TOOL_ERROR_OPEN = "<tool_use_error>"
TOOL_ERROR_CLOSE = "</tool_use_error>"
REASON_MARKER = "Reason:"

EXCERPT_LIMIT = 320
COMMAND_LIMIT = 200


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--uuid", help="Session UUID to discover (main + subagents).")
    p.add_argument("--projects-dir", default=None,
                   help="Claude projects root. Default: ~/.config/claude-code/projects "
                        "(falls back to ~/.claude/projects).")
    p.add_argument("--files", nargs="+",
                   help="Explicit transcript files instead of --uuid discovery.")
    return p.parse_args()


def default_projects_dirs() -> List[str]:
    return [os.path.expanduser("~/.config/claude-code/projects"),
            os.path.expanduser("~/.claude/projects")]


def discover_files(uuid: str, projects_dir: Optional[str]) -> List[str]:
    """Find a session's main transcript + every subagent transcript, by UUID.

    Searches every slug dir (worktree sessions get their own slug), so we never
    have to reconstruct the slug from the cwd.
    """
    roots = [projects_dir] if projects_dir else default_projects_dirs()
    files: List[str] = []
    for root in roots:
        if not root or not os.path.isdir(root):
            continue
        files += glob.glob(os.path.join(root, "*", f"{uuid}.jsonl"))
        files += glob.glob(os.path.join(root, "*", uuid, "subagents", "*.jsonl"))
    # de-dup, stable order: main transcripts first
    seen, ordered = set(), []
    for f in sorted(files, key=lambda p: ("subagents" in p, p)):
        if f not in seen:
            seen.add(f)
            ordered.append(f)
    return ordered


def is_subagent(path: str) -> bool:
    return os.sep + "subagents" + os.sep in path


def load_meta(sub_path: str) -> Dict[str, Optional[str]]:
    meta_path = sub_path[:-len(".jsonl")] + ".meta.json"
    try:
        with open(meta_path, encoding="utf-8") as fh:
            data = json.load(fh)
        return {"agent_type": data.get("agentType"),
                "agent_description": data.get("description")}
    except (OSError, ValueError):
        return {"agent_type": None, "agent_description": None}


def extract_text(content: object) -> str:
    """tool_result content is usually a str; tolerate the list-of-blocks shape too."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for it in content:
            if isinstance(it, str):
                parts.append(it)
            elif isinstance(it, dict) and isinstance(it.get("text"), str):
                parts.append(it["text"])
        return "\n".join(parts)
    return ""


def normalize_input(tool: Optional[str], inp: object) -> str:
    """A retry key: same tool + near-identical input. Collapse whitespace so trivial
    reformatting of a re-issued command still counts as the same command."""
    if not isinstance(inp, dict):
        return repr(inp)[:COMMAND_LIMIT]
    if tool == "Bash":
        return " ".join((inp.get("command") or "").split())
    if tool in ("Write", "Edit", "Read", "NotebookEdit"):
        return str(inp.get("file_path") or inp.get("notebook_path") or "")
    return json.dumps({k: str(v)[:60] for k, v in sorted(inp.items())},
                      ensure_ascii=False)


def command_display(tool: Optional[str], inp: object) -> Optional[str]:
    if not isinstance(inp, dict):
        return None
    if tool == "Bash":
        return " ".join((inp.get("command") or "").split())[:COMMAND_LIMIT]
    if tool in ("Write", "Edit", "Read", "NotebookEdit"):
        return str(inp.get("file_path") or inp.get("notebook_path") or "")
    if tool == "Skill":
        return str(inp.get("skill") or inp.get("command") or "")
    return normalize_input(tool, inp)[:COMMAND_LIMIT]


def clean_excerpt(text: str) -> str:
    t = text.strip()
    if t.startswith(TOOL_ERROR_OPEN):
        t = t[len(TOOL_ERROR_OPEN):]
    t = t.replace(TOOL_ERROR_CLOSE, "").replace(TOOL_ERROR_OPEN, "")
    t = " ".join(t.split())
    return t[:EXCERPT_LIMIT]


def classify(text: str) -> Tuple[str, Optional[str]]:
    """Return (error_class, denial_reason)."""
    low = text.lower()
    if PERMISSION_MARKER in text:
        reason = None
        idx = text.find(REASON_MARKER)
        if idx >= 0:
            reason = text[idx + len(REASON_MARKER):].strip()
            reason = " ".join(reason.split())[:EXCERPT_LIMIT]
        return "permission_denied", reason
    if any(m in low for m in REJECTION_MARKERS):
        return "user_rejected", None
    if TOOL_ERROR_OPEN in text:
        return "tool_error", None
    return "runtime_error", None


def scan(files: List[str]):
    """Stream the session's files; return (tool_uses, invocations, errors)."""
    tool_uses: Dict[str, Tuple[Optional[str], object]] = {}      # id -> (name, input)
    invocations: Dict[str, int] = {}                             # retry-key -> count
    errors: List[dict] = []                                      # raw error records

    for fp in files:
        src = "subagent" if is_subagent(fp) else "main"
        meta = load_meta(fp) if src == "subagent" else {"agent_type": None,
                                                         "agent_description": None}
        try:
            fh = open(fp, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    obj = json.loads(raw)
                except ValueError:
                    continue
                msg = obj.get("message")
                if not isinstance(msg, dict):
                    continue
                ts = obj.get("timestamp")
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use" and isinstance(b.get("id"), str):
                        name, inp = b.get("name"), b.get("input")
                        tool_uses[b["id"]] = (name, inp)
                        key = f"{name}\x00{normalize_input(name, inp)}"
                        invocations[key] = invocations.get(key, 0) + 1
                    elif (b.get("type") == "tool_result" and b.get("is_error")
                          and isinstance(b.get("tool_use_id"), str)):
                        errors.append({
                            "tool_use_id": b["tool_use_id"],
                            "text": extract_text(b.get("content")),
                            "timestamp": ts if isinstance(ts, str) else None,
                            "source": src,
                            "agent_type": meta["agent_type"],
                            "agent_description": meta["agent_description"],
                        })
    return tool_uses, invocations, errors


def build_candidates(tool_uses, invocations, errors) -> List[dict]:
    candidates = []
    # error_count per retry-key, so the fork can see a command that *kept* failing
    error_keys: Dict[str, int] = {}
    resolved = []
    for e in errors:
        name, inp = tool_uses.get(e["tool_use_id"], (None, None))
        key = f"{name}\x00{normalize_input(name, inp)}" if name else None
        if key:
            error_keys[key] = error_keys.get(key, 0) + 1
        resolved.append((e, name, inp, key))

    for e, name, inp, key in resolved:
        error_class, denial_reason = classify(e["text"])
        cand = {
            "source": e["source"],
            "tool": name,
            "command": command_display(name, inp),
            "error_class": error_class,
            "error_excerpt": clean_excerpt(e["text"]),
            "denial_reason": denial_reason,
            "retry_count": invocations.get(key, 1) if key else 1,
            "error_count": error_keys.get(key, 1) if key else 1,
            "timestamp": e["timestamp"],
            "tool_use_id": e["tool_use_id"],
        }
        if e["source"] == "subagent":
            cand["agent_type"] = e["agent_type"]
            cand["agent_description"] = e["agent_description"]
        candidates.append(cand)
    return candidates


def main() -> int:
    args = parse_args()
    if args.files:
        files = [f for f in args.files if os.path.isfile(f)]
    elif args.uuid:
        files = discover_files(args.uuid, args.projects_dir)
    else:
        print("error: pass --uuid or --files", file=sys.stderr)
        return 2

    if not files:
        print(json.dumps({
            "summary": {"session_uuid": args.uuid, "files_scanned": 0,
                        "candidates": 0, "note": "no transcripts found for this UUID"},
            "candidates": []}, indent=2))
        return 0

    tool_uses, invocations, errors = scan(files)
    candidates = build_candidates(tool_uses, invocations, errors)

    by_class: Dict[str, int] = {}
    for c in candidates:
        by_class[c["error_class"]] = by_class.get(c["error_class"], 0) + 1

    report = {
        "summary": {
            "session_uuid": args.uuid,
            "files_scanned": len(files),
            "main_files": sum(1 for f in files if not is_subagent(f)),
            "subagent_files": sum(1 for f in files if is_subagent(f)),
            "candidates": len(candidates),
            "by_class": by_class,
        },
        "candidates": candidates,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
