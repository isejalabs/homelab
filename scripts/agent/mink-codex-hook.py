#!/usr/bin/env python3
"""Translate Codex hook events to Mink's Claude-compatible file events.

Shell read detection is deliberately conservative: only standalone cat/head/tail
and numeric sed print commands are recognized. No shell text is executed here.
Mink output replacement is discarded because Codex does not support that field.
"""

import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys


def shell_reads(command, cwd):
    """Recognize explicit file operands, never expand shell expressions."""
    if any(char in command for char in "\n;|&<>`$()"):
        return []
    try:
        args = shlex.split(command)
    except ValueError:
        return []
    if not args:
        return []
    name, args = Path(args[0]).name, args[1:]
    ranged = name != "cat"
    if name == "sed":
        if len(args) < 3 or args[0] != "-n" or not re.fullmatch(r"\d+(,\d+)?p", args[1]):
            return []
        args = args[2:]
    elif name in ("head", "tail"):
        if args[:1] in (["-n"], ["-c"]):
            if len(args) < 3 or not re.fullmatch(r"[+-]?\d+", args[1]):
                return []
            args = args[2:]
        elif args and re.fullmatch(r"-\d+", args[0]):
            args = args[1:]
    elif name != "cat":
        return []
    if args[:1] == ["--"]:
        args = args[1:]
    if any(arg.startswith("-") or any(c in arg for c in "*?[]~") for arg in args):
        return []
    reads = []
    for arg in dict.fromkeys(args):
        path = (cwd / arg).resolve()
        # Do not turn a guessed shell operand into a read outside the project.
        if path.is_relative_to(cwd) and path.is_file():
            fields = {"file_path": str(path)}
            if ranged:
                fields["offset"] = 1
            reads.append(("Read", fields))
    return reads


def patch_writes(patch, cwd):
    """Extract every changed path and added text from an apply_patch command."""
    if not patch.startswith("*** Begin Patch\n") or "*** End Patch" not in patch.splitlines():
        return []
    writes = []
    current = None
    for line in patch.splitlines():
        match = re.fullmatch(r"\*\*\* (Add|Update|Delete) File: (.+)", line)
        if match:
            kind, path = match.groups()
            current = {"kind": kind, "path": path, "added": []}
            writes.append(current)
        elif line.startswith("*** Move to: ") and current:
            # Track both deletion of the old path and the new destination.
            old = current["path"]
            current["path"] = line[len("*** Move to: "):]
            writes.append({"kind": "Delete", "path": old, "added": []})
        elif line.startswith("+") and current:
            current["added"].append(line[1:])
    events = []
    for write in writes:
        name = "Write" if write["kind"] == "Add" else "Edit"
        fields = {"file_path": str((cwd / write["path"]).resolve())}
        fields["content" if name == "Write" else "new_string"] = "\n".join(write["added"])
        events.append((name, fields))
    return events


def file_events(event, cwd):
    name = event.get("tool_name")
    fields = event.get("tool_input", {})
    if not isinstance(fields, dict):
        return []
    if name == "apply_patch":
        return patch_writes(fields.get("command", ""), cwd)
    if name == "Bash":
        return shell_reads(fields.get("command", ""), cwd)
    if name in ("Read", "Edit", "Write") and fields.get("file_path"):
        return [(name, fields)]
    return []


def mink_executable():
    binary = shutil.which("mink")
    fallback = Path.home() / ".bun/bin/mink"
    if binary:
        return binary
    if fallback.is_file():
        return str(fallback)
    raise RuntimeError("mink executable not found")


def run_mink(command, event, cwd):
    env = os.environ.copy()
    # The desktop hook process may not inherit the interactive shell's PATH.
    env["PATH"] = str(Path.home() / ".bun/bin") + os.pathsep + env.get("PATH", "")
    result = subprocess.run(
        [mink_executable(), command], input=json.dumps(event), text=True,
        capture_output=True, cwd=cwd, env=env, timeout=25, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"mink {command} exited {result.returncode}: {result.stderr.strip()}")
    # Mink's stdout contains unsupported updatedToolOutput responses. Only
    # forward diagnostics, using Codex's additionalContext contract.
    return result.stderr.strip()


def handle(event, runner=run_mink):
    cwd = Path(event.get("cwd", os.getcwd())).resolve()
    kind = event.get("hook_event_name")
    messages = []
    if kind in ("SessionStart", "Stop"):
        command = "session-start" if kind == "SessionStart" else "session-stop"
        messages.append(runner(command, event, cwd))
    elif kind in ("PreToolUse", "PostToolUse"):
        response = event.get("tool_response", {})
        if kind == "PostToolUse" and isinstance(response, dict):
            if response.get("exit_code", 0) not in (0, None) or response.get("isError"):
                return {}
        prefix = "pre" if kind == "PreToolUse" else "post"
        for name, fields in file_events(event, cwd):
            translated = dict(event, tool_name=name, tool_input=fields)
            messages.append(runner(f"{prefix}-{'read' if name == 'Read' else 'write'}", translated, cwd))
    context = "\n".join(message for message in messages if message)
    if not context:
        return {}
    if kind == "Stop":
        return {"systemMessage": context}
    return {"hookSpecificOutput": {"hookEventName": kind, "additionalContext": context}}


def main():
    try:
        event = json.load(sys.stdin)
        # Mink updates a shared project session.json by read/modify/write.
        # Serialize adapter invocations so parallel Codex calls do not lose data.
        root = Path(os.environ.get("MINK_ROOT_OVERRIDE", str(Path.home() / ".mink")))
        root.mkdir(parents=True, exist_ok=True)
        with (root / "codex-hook.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = handle(event)
        if result:
            print(json.dumps(result))
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        # Visible, non-blocking diagnostics instead of Mink's silent failures.
        print(json.dumps({"systemMessage": f"Mink Codex adapter: {error}"}))


if __name__ == "__main__":
    main()
