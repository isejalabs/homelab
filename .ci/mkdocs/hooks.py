"""MkDocs hooks for the docs site (see docs/decisions/0017-docs-site-generator.md).

The repository's Markdown stays the single source of truth and is read as-is on github.com, so nothing
is rewritten on disk; these hooks only adjust the rendered site:

* links that leave the served pages (source files, directories, workflow files, files excluded from the
  site) are rewritten to the matching github.com blob/tree URL, since the target does not exist on the site;
* a visible status banner is added below the page title, from the `status:` front matter, the ADR
  `## Status` section, or the folder (audits and plans are dated snapshots);
* a robots.txt is written while `extra.noindex` is set in mkdocs.yml.
"""

import os
import posixpath
import re
from urllib.parse import unquote

REPO_URL = "https://github.com/isejalabs/homelab"
BRANCH = "main"

FENCE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN = re.compile(r"(`+[^`]*`+)")
INLINE_LINK = re.compile(r"(\]\()(<[^>]+>|[^)\s]+)((?:\s+(?:\"[^\"]*\"|'[^']*'))?\))")
REFERENCE_DEF = re.compile(r"^(\s{0,3}\[[^\]]+\]:\s*)(\S+)")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
TITLE = re.compile(r"^# ")
ADR_STATUS = re.compile(r"^## Status\s*\n+\s*([A-Za-z]+)", re.MULTILINE)

# status -> (admonition type, label, text)
BANNERS = {
    "current": ("success", "Status: current", "Describes the system as it is today."),
    "planning": ("info", "Status: planning", "Describes an intended or not-yet-implemented design."),
    "historical": ("warning", "Status: historical", "Superseded; kept for context, not a guide to today's system."),
    "superseded": ("warning", "Status: superseded", "Replaced by a later decision; kept for context."),
    "audit": (
        "warning",
        "Dated audit",
        "A point-in-time assessment, never edited after the fact. It is not current-state documentation.",
    ),
    "plan": (
        "warning",
        "Dated plan",
        "An implementation plan that follows from an audit. Check its own Status line; it is not current-state documentation.",
    ),
}


def _repo_root(config):
    return os.path.abspath(config["docs_dir"])


def _github_url(path, root):
    """Return the github.com URL for a repo-relative path, or None if it does not exist in the checkout."""
    full = os.path.join(root, *path.split("/"))
    if os.path.isdir(full):
        return f"{REPO_URL}/tree/{BRANCH}/{path.rstrip('/')}"
    if os.path.isfile(full):
        return f"{REPO_URL}/blob/{BRANCH}/{path}"
    return None


def _rewrite_target(target, page, files, root):
    wrapped = target.startswith("<") and target.endswith(">")
    raw = target[1:-1] if wrapped else target
    if not raw or raw.startswith(("#", "/", "?")) or SCHEME.match(raw):
        return target
    path_part, hash_sep, fragment = raw.partition("#")
    path = unquote(path_part)
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(page.file.src_uri), path))
    if resolved.startswith("..") or resolved == ".":
        return target
    served = files.get_file_from_path(resolved)
    if served is not None and not served.inclusion.is_excluded():
        return target
    url = _github_url(resolved, root)
    if url is None:
        return target  # leave it: MkDocs reports it and --strict fails the build
    url += hash_sep + fragment
    return f"<{url}>" if wrapped else url


def _rewrite_links(markdown, page, files, root):
    out = []
    in_fence = False
    for line in markdown.split("\n"):
        if FENCE.match(line):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        ref = REFERENCE_DEF.match(line)
        if ref:
            line = ref.group(1) + _rewrite_target(ref.group(2), page, files, root) + line[ref.end():]
        pieces = CODE_SPAN.split(line)
        for i in range(0, len(pieces), 2):  # even indexes are outside code spans
            pieces[i] = INLINE_LINK.sub(
                lambda m: m.group(1) + _rewrite_target(m.group(2), page, files, root) + m.group(3), pieces[i]
            )
        out.append("".join(pieces))
    return "\n".join(out)


def _status_for(page, markdown):
    src = page.file.src_uri
    name = posixpath.basename(src)
    status = page.meta.get("status")
    if status:
        return str(status).strip().lower()
    if src.startswith("docs/decisions/") and name != "README.md":
        match = ADR_STATUS.search(markdown)
        return match.group(1).lower() if match else None
    if src.startswith("docs/audits/") and name != "README.md":
        return "audit"
    if src.startswith("docs/plans/") and name != "README.md":
        return "plan"
    return None


def _add_banner(markdown, status):
    banner = BANNERS.get(status)
    if banner is None:
        return markdown
    kind, label, text = banner
    block = f'!!! {kind} "{label}"\n    {text}\n'
    lines = markdown.split("\n")
    in_fence = False
    for i, line in enumerate(lines):
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence and TITLE.match(line):
            return "\n".join(lines[: i + 1] + ["", *block.split("\n"), *lines[i + 1 :]])
    return block + "\n" + markdown


def on_page_markdown(markdown, page, config, files):
    markdown = _rewrite_links(markdown, page, files, _repo_root(config))
    status = _status_for(page, markdown)
    return _add_banner(markdown, status) if status else markdown


def on_post_build(config):
    if config.get("extra", {}).get("noindex"):
        with open(os.path.join(config["site_dir"], "robots.txt"), "w", encoding="utf-8") as f:
            f.write("User-agent: *\nDisallow: /\n")
