#!/usr/bin/env python3
"""Block a command that would publish a term from the private disclosure list.

Runs as a Claude Code PreToolUse hook on Bash (see .claude/settings.json). The disclosure-private-terms
pre-commit hook only reads files, so the text of issues, pull requests, comments and commit messages was
never checked (ADR 0019, issue 2332). This hook closes that gap at the moment of publishing: for a gh
write command, a gh api call or git commit/tag, it checks the command text and the files the command
names with --body-file, --notes-file, --file or -F through scripts/tools/check-private-terms.sh, the same script and
list as the pre-commit hook. A hit exits 2, which blocks the command and shows the reason to the agent.

The reason only names where the hit is, never the term: check-private-terms.sh prints file:line only. A
machine without a private list is a no-op, and an unusable list or a missing script only warns, so the
hook never stops work for a reason that is not a hit. It does not execute any of the shell text.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

CHECK = Path(__file__).resolve().parent.parent / "tools" / "check-private-terms.sh"

# Commands that publish text: gh issue/pr/release/discussion writes, any gh api call and git commit/tag.
PUBLISHING = re.compile(
    r"(?:^|[\s;&|(`])(?:"
    r"gh\s+(?:issue|pr|release|discussion)\s+(?:create|edit|comment|review|merge|close|reopen|delete-comment)"
    r"|gh\s+api"
    r"|git\s+(?:-\S+\s+)*(?:commit|tag)"
    r")\b"
)
# Files whose content is posted: --body-file, --notes-file, --file, -F (gh) and -F, --file (git commit).
TEXT_FILE = re.compile(r"(?:--body-file|--notes-file|--file|-F)(?:\s+|=)(?:'([^']+)'|\"([^\"]+)\"|(\S+))")
MAX_BYTES = 1_000_000


def referenced_files(command):
    """Return the readable files a command names as the source of its text, as Paths."""
    files = []
    for match in TEXT_FILE.finditer(command):
        raw = next(group for group in match.groups() if group)
        if raw in ("-", "") or "$" in raw or "`" in raw:
            continue
        path = Path(os.path.expanduser(raw))
        if path.is_file() and path.stat().st_size <= MAX_BYTES:
            files.append(path)
    return files


def check(path):
    """Run check-private-terms.sh on one file; return (exit status, its output)."""
    result = subprocess.run(
        ["sh", str(CHECK), str(path)], capture_output=True, text=True, check=False
    )
    return result.returncode, (result.stdout + result.stderr).strip()


def main():
    """Read the hook event from stdin and exit 2 with a reason when the text contains a listed term."""
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (event.get("tool_input") or {}).get("command") or ""
    if not PUBLISHING.search(command) or not CHECK.is_file():
        return 0

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        # The command text itself carries a heredoc body or a -m message; the check script reads files.
        text = Path(tmp) / "command-text"
        text.write_text(command)
        targets = [("the command text", text)] + [(str(p), p) for p in referenced_files(command)]
        for label, path in targets:
            status, output = check(path)
            if status == 1:
                lines = ",".join(
                    line.split(":")[-2] for line in output.splitlines() if line.endswith("private list")
                )
                problems.append(f"{label} (line {lines})")
            elif status not in (0, 1):
                print(f"disclosure-pre-publish: could not check ({output.splitlines()[-1] if output else status})", file=sys.stderr)
                return 1

    if problems:
        print(
            "Blocked by the disclosure guard (ADR 0019): " + "; ".join(problems) + " contains a term from the "
            "private list. Replace it by a placeholder, write the text to a file, run "
            "scripts/tools/check-private-terms.sh on it and publish that file (--body-file / git commit -F). "
            "Do not read the list.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
