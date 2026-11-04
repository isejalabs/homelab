"""MkDocs hooks for the docs site (see docs/decisions/0017-docs-site-generator.md).

The repository's Markdown stays the single source of truth and is read as-is on github.com, so nothing
is rewritten on disk; these hooks only adjust the rendered site:

* links that leave the served pages (source files, directories, workflow files, files excluded from the
  site) are rewritten to the matching github.com blob/tree URL, since the target does not exist on the site;
* the relative `src` of a raw HTML `<img>` is rewritten to the image's URL relative to the page: MkDocs only
  resolves Markdown images, and a page is served one directory deeper than its source file (`docs/a/b.md` is
  `docs/a/b/`), so the path that works on github.com would be one level off on the site;
* a visible status banner is added below the page title, from the `status:` front matter when it is one of the
  labels in BANNERS, otherwise from the folder (audits and plans are dated snapshots, whose `status:` is free text);
* the rest of the front matter (date, scope, origin, tracking, ...) is shown as a metadata block below the banner;
* the footer of each page names the last git commit that changed that page's source file (ID, head line and
  date), read from the checkout; it needs the full history, so a shallow clone leaves the footer out;
* a robots.txt is written while `extra.noindex` is set in mkdocs.yml.
"""

import html
import logging
import os
import posixpath
import re
import subprocess
from urllib.parse import unquote

log = logging.getLogger("mkdocs.hooks.footer")
_footer = {"enabled": False}  # set in on_config: whether the history is deep enough to name a page's last commit

REPO_URL = "https://github.com/isejalabs/homelab"
BRANCH = "main"

FENCE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN = re.compile(r"(`+[^`]*`+)")
IMG_SRC = re.compile(r"(<img\b[^>]*?\bsrc=\")([^\"]+)(\")")
INLINE_LINK = re.compile(r"(\]\()(<[^>]+>|[^)\s]+)((?:\s+(?:\"[^\"]*\"|'[^']*'))?\))")
REFERENCE_DEF = re.compile(r"^(\s{0,3}\[[^\]]+\]:\s*)(\S+)")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
TITLE = re.compile(r"^# ")
# a bare reference in a front matter value: an absolute URL, or a relative path to a Markdown file with an optional #anchor
META_REF = re.compile(r"(https?://[^\s,;)]+[^\s,;).])|(?<![\w/.:#-])((?:\.{1,2}/)*(?:[\w.-]+/)*[\w-][\w.-]*\.md)(#[\w-]+)?")
GITHUB_ITEM = re.compile(r"https://github\.com/([^/]+/[^/]+)/(?:issues|pull)/(\d+)$")

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


def _is_shallow(root):
    """Return True if the checkout has truncated history, where `git log -- <file>` names the wrong commit."""
    try:
        out = subprocess.run(
            ["git", "-C", root, "rev-parse", "--is-shallow-repository"],
            check=True, capture_output=True, text=True, timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return out.strip() == "true"


def _last_commit(root, src_uri):
    """Return (full SHA, short SHA, subject, date) of the last commit that changed `src_uri`, or None.

    None means there is nothing to show: not a git checkout, or the file has no commit yet (a new, uncommitted
    page in a local preview).
    """
    try:
        out = subprocess.run(
            ["git", "-C", root, "log", "-1", "--format=%H%n%h%n%cs%n%s", "--", src_uri],
            check=True, capture_output=True, text=True, timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    parts = out.rstrip("\n").split("\n", 3)
    if len(parts) != 4 or not parts[0]:
        return None
    sha, short, date, subject = parts
    return sha, short, subject, date


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


def _rewrite_img_src(match, page, files):
    """Return the raw `<img>` tag with a relative `src` made relative to the page's URL; other sources stay."""
    src = match.group(2)
    if not src or src.startswith(("#", "/", "?")) or SCHEME.match(src):
        return match.group(0)
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(page.file.src_uri), unquote(src)))
    served = files.get_file_from_path(resolved)
    if served is None or served.inclusion.is_excluded():
        return match.group(0)
    return match.group(1) + served.url_relative_to(page.file) + match.group(3)


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
            pieces[i] = IMG_SRC.sub(lambda m: _rewrite_img_src(m, page, files), pieces[i])
        out.append("".join(pieces))
    return "\n".join(out)


def _status_for(page):
    """Return the BANNERS key for a page, or None.

    The `status:` front matter wins when it is one of the labels. Audits and plans use `status:` for free text
    (how complete the assessment is), which is no label, so they fall back to their folder. An ADR without a label
    is reported, since nothing else would show that its banner is missing.
    """
    src = page.file.src_uri
    name = posixpath.basename(src)
    status = str(page.meta.get("status") or "").strip().lower()
    if status in BANNERS:
        return status
    if src.startswith("docs/audits/") and name != "README.md":
        return "audit"
    if src.startswith("docs/plans/") and name != "README.md":
        return "plan"
    if src.startswith("docs/decisions/") and name != "README.md":
        log.warning("%s: an ADR needs `status: current|planning|superseded` front matter", src)
    return None


def _meta_ref(match):
    """Return a Markdown link for a bare URL or relative `.md` path of a front matter value.

    github.com shows front matter as plain text, where it turns a bare URL into `#1437` but shows Markdown link syntax
    as written, so the values hold bare references and the link is made here. An issue or pull request is labelled
    `#N` (`owner/repo#N` outside this repository), another URL by itself, a path by its file name.
    """
    if match.group(1):
        url = match.group(1)
        item = GITHUB_ITEM.match(url)
        if item:
            repo = item.group(1)
            return f"[{'' if repo == 'isejalabs/homelab' else repo}#{item.group(2)}]({url})"
        return f"[{url.split('://', 1)[1]}]({url})"
    path, anchor = match.group(2), match.group(3) or ""
    return f"[`{posixpath.basename(path)}`]({path}{anchor})"


def _linkify(value):
    """Turn the bare references of a front matter value into links, leaving code spans alone."""
    pieces = CODE_SPAN.split(value)
    for i in range(0, len(pieces), 2):
        pieces[i] = META_REF.sub(_meta_ref, pieces[i])
    return "".join(pieces)


def _meta_block(meta):
    """Return the front matter as a raw-HTML definition list (values are inline Markdown), or "" if nothing is left to show.

    `status` is skipped when it is a BANNERS label, since the banner already says it; any other key is shown in file
    order, labelled by its name (`builds-on` -> "Builds on"). Values are plain YAML text; bare URLs and relative `.md`
    paths become links (see `_meta_ref`), and `md_in_html` renders the `markdown="span"` values, so code spans work.
    """
    rows = []
    for key, value in meta.items():
        if value in (None, "", []):
            continue
        if key == "status" and str(value).strip().lower() in BANNERS:
            continue
        if isinstance(value, (list, tuple)):
            value = ", ".join(str(v) for v in value)
        label = html.escape(key.replace("-", " ").capitalize())
        rows.append(f'<dt>{label}</dt>\n<dd markdown="span">{_linkify(str(value).strip())}</dd>')
    if not rows:
        return ""
    return '<dl class="doc-meta" markdown="block">\n' + "\n".join(rows) + "\n</dl>"


def _add_blocks(markdown, blocks):
    """Insert the blocks, separated by blank lines, right below the page title (or at the top without one)."""
    insert = "\n\n".join(blocks)
    lines = markdown.split("\n")
    in_fence = False
    for i, line in enumerate(lines):
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence and TITLE.match(line):
            return "\n".join(lines[: i + 1] + ["", *insert.split("\n"), *lines[i + 1 :]])
    return insert + "\n\n" + markdown


def _banner(status):
    kind, label, text = BANNERS[status]
    return f'!!! {kind} "{label}"\n    {text}'


def on_config(config):
    """Start with no footer text and note up front when the history is too short to name a page's commit."""
    config["copyright"] = ""
    _footer["enabled"] = not _is_shallow(_repo_root(config))
    if not _footer["enabled"]:
        log.info("shallow git checkout: the per-page last-commit footer is left out (fetch full history to get it)")
    return config


def on_page_context(context, page, config, nav):
    """Name the last commit that changed this page's source file in the footer (the theme prints `copyright` there).

    The footer is per page, not per build: a page that was last touched months ago must not claim the commit the
    site happens to be built from. `copyright` is shared state, so it is set for every page and reset in
    `on_post_page`.
    """
    config["copyright"] = ""
    if _footer["enabled"]:
        commit = _last_commit(_repo_root(config), page.file.src_uri)
        if commit:
            sha, short, subject, date = commit
            config["copyright"] = (
                f'Last changed in commit <a href="{REPO_URL}/commit/{sha}"><code>{short}</code></a>'
                f" &ndash; {html.escape(subject)} ({date})"
            )
    return context


def on_post_page(output, page, config):
    """Drop the page's footer text again so a template rendered later (404, sitemap) never shows another page's."""
    config["copyright"] = ""
    return output


def on_page_markdown(markdown, page, config, files):
    status = _status_for(page)
    blocks = [b for b in (_banner(status) if status else "", _meta_block(page.meta)) if b]
    if blocks:
        markdown = _add_blocks(markdown, blocks)
    return _rewrite_links(markdown, page, files, _repo_root(config))


def on_post_build(config):
    if config.get("extra", {}).get("noindex"):
        with open(os.path.join(config["site_dir"], "robots.txt"), "w", encoding="utf-8") as f:
            f.write("User-agent: *\nDisallow: /\n")
