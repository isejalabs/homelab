# Documentation site generator: MkDocs with the Material theme

## Status

current

## Context

The documentation is Markdown in `docs/` plus READMEs colocated with the code they describe (see [`docs/README.md`](../README.md)). It is readable on github.com but has no search, no sidebar and no navigation beyond hand-maintained index tables ([#2027](https://github.com/isejalabs/homelab/issues/2027), finding S1 of the [second October 2026 documentation audit](../audits/2026-10-documentation-claude.md)). The Markdown must stay the single source of truth, so the site is a rendering of it, not a second copy.

Requirements specific to this repo, which decide the choice more than the look does:

- Pages come from outside `docs/` (root and per-folder READMEs), which must not move.
- Relative links to source files and directories, which do not exist on a site, have to be rewritten to github.com while staying relative on github.com and in the `docs-link-check` workflow.
- A broken link or anchor has to fail the build.
- The `status:` front matter, the ADR `## Status` section and the dated audits and plans have to be visible on the page.
- Mermaid fences have to render ([#2028](https://github.com/isejalabs/homelab/issues/2028)).
- The toolchain has to be pinnable and covered by Renovate, like every other tool here.

Status of the candidates, checked on 2026-10-31:

- Material for MkDocs is in maintenance mode: its README states end of life on 2027-05-05, with critical fixes and security updates until then. Version 9.8.0 was still released on 2026-10-24. The MkDocs core itself is stuck at 1.6.1 (released 2024-08-30), and Material pins `mkdocs<2`.
- Zensical, from the same authors and announced as the successor, is at 0.0.74 (2026-10-30), MIT-licensed, reads an existing `mkdocs.yml`, and has only `build`, `new` and `serve` commands. The installed package contains no hook mechanism and the CLI has no `--strict` flag.

## Options considered

- **MkDocs with Material, pinned (chosen)** — supports everything above today: `docs_dir` at the repository root with `exclude_docs`, Python hooks (`on_page_markdown`) for the link rewrite and the status banner, `--strict` with anchor validation, Mermaid through `pymdownx.superfences`, light/dark palette, search. Simple Python toolchain with a pinned `requirements.txt` that Renovate already understands. Cost: end of life on 2027-05-05 and a core that is no longer developed.
- **Zensical (rejected for now)** — the natural successor and a near drop-in for the configuration, but at 0.0.x it cannot yet do the link rewrite (no hooks) and cannot fail on warnings (no `--strict`), both of which are requirements here. Revisit when it has hooks or an equivalent extension point, strict mode, and a 1.x release line.
- **Docusaurus (rejected)** — React and a Node toolchain to maintain for what is a Markdown tree. Its MDX parsing is stricter than GitHub's, so plain Markdown that renders fine on github.com (stray `<`, `{`) can break the build, which conflicts with "Markdown stays the single source of truth". Docs outside its docs folder need extra plugins; Mermaid needs a theme package.
- **Starlight (Astro) (rejected)** — a good fit for a fresh docs site, but the same costs: a Node toolchain, MDX/content-collection conventions, and custom remark plugins for the out-of-folder READMEs and the link rewrite. No gain over MkDocs for a docs tree that already exists.

## Decision

Build the site with MkDocs and the Material theme, versions pinned in [`.ci/mkdocs/requirements.txt`](../../.ci/mkdocs/requirements.txt) and updated by Renovate. The configuration is [`.ci/mkdocs/mkdocs.yml`](../../.ci/mkdocs/mkdocs.yml) (MkDocs refuses a `docs_dir` that contains `mkdocs.yml`, so it cannot sit at the root while the root is the docs directory) and the hooks are [`.ci/mkdocs/hooks.py`](../../.ci/mkdocs/hooks.py). Planned exit: migrate to Zensical once it meets the conditions above, and in any case before the end of life on 2027-05-05, tracked as a follow-up of [#2027](https://github.com/isejalabs/homelab/issues/2027).

Not part of this decision: whether the site is public. That is the owner's call under [#1601](https://github.com/isejalabs/homelab/issues/1601). The site ships with `noindex` and a restrictive `robots.txt`, and the deploy job only runs when the repository variable `DOCS_PAGES_PUBLISH` is `true`.

## Consequences

- The whole checkout is the `docs_dir`, so everything not Markdown or an image, and everything that is not documentation (`.github/`, `.agents/`, `_attic/`, `ZZ.bak/`, `docs/logs/`, `AGENTS.md`), is excluded in `exclude_docs`. A new documentation directory outside `docs/` needs no change; a new top-level directory with Markdown that is not documentation does.
- A page that should appear in the sidebar has to be added to `nav`. Pages missing from it are still built and searchable; MkDocs only reports them at `INFO` level.
- Heading anchors use GitHub-compatible slugs, so `#anchor` links behave the same on github.com and on the site, and `--strict` turns a broken one into a failed build.
- Links from a page to a file or directory that is not part of the site resolve to `https://github.com/isejalabs/homelab/blob/main/...` or `.../tree/main/...` at build time. A link to a path that does not exist anywhere is left alone, so the build fails on it.
- Mermaid is rendered in the browser by a script that Material loads at runtime from a CDN; the site has that runtime dependency only on pages with a Mermaid fence.
- Maintenance mode of the theme is accepted knowingly; the cost of the later migration is expected to be small because the content, the front matter and the configuration are already tool-neutral.
