# Branch naming and development conventions

## Branch names: `issue/<issue-number>_<shorttext>`

Every branch for real work is named `issue/<issue-number>_<shorttext>`, e.g. `issue/123_fix-flux-dependson`.
Never ship a change on an ad hoc or harness-generated name (e.g. a Claude Code on the web `claude/fancy-foo`
branch) — treat that as a starting point to rename/recreate from, not the final branch, unless the session's
own instructions explicitly pin it to that name (in which case say so rather than silently renaming mid-session).

- `<issue-number>` is a GitHub issue number in this repo — never a placeholder, and never the number of a PR
  or an issue in another repo.
- `<shorttext>` is a short kebab-case slug summarizing the change — same spirit as the Conventional Commits
  scope (see `CLAUDE.md`'s Conventions), not the issue title copied verbatim.

## An issue is a prerequisite, not an afterthought

A branch/PR needs an issue number before it exists, so resolve that first:

1. **Request already names an issue** (e.g. "fix #123", a linked issue URL) → use that number directly.
2. **Request doesn't name one, but has enough detail to write one** (a clear problem statement,
   the expectations/acceptance criteria implicit in what's being asked) → create the issue first from
   that detail, then use the number GitHub assigns it. Don't ask the user to restate what they already
   said in the prompt just to fill out an issue body — extract it.
3. **Request is too vague to state a clear issue body** → ask the user for the issue number, or for
   enough detail to create one (per case 2) — whichever is faster. Don't guess.

Never invent a placeholder issue number, and never open the PR/start committing before the issue exists —
the branch name depends on it.

## No feature/bugfix PR merges without a related issue

This isn't limited to PRs that already follow the `issue/<n>_...` branch convention above — it's a hard
requirement for any feature or bugfix PR in this repo, regardless of who or what opened it. The one
exception is Renovate's own dependency-update PRs, which aren't feature/bugfix work and don't need one.

- The PR body must reference the issue describing the problem it's solving — a closing keyword
  (`Closes #123`/`Fixes #123`/`Resolves #123`) when this PR is the one that fully resolves the issue, or
  a plain reference (`Relates to #123`) when it's one step of multi-part work and isn't meant to close the
  issue yet. Not fully solving the issue in one PR is fine; having no issue behind the PR at all is not.
- Check this on every PR, not just ones you open yourself: a PR opened by other tooling from an
  `issue/<n>_...` branch (e.g. Claude Code on the web's own "create a PR for this branch" flow) has no
  reason to know about this repo's convention and won't add it — if the body is missing a reference to the
  issue named in the branch, edit it in rather than leaving the link implicit.
- Before calling any PR mergeable, confirm every issue number it mentions actually exists (open it, don't
  just trust the number in the text) — a typo'd, wrong-repo, or hallucinated issue number is worse than no
  reference at all, since it reads as resolved when it isn't.

Per-issue local session-state files (e.g. `.dev/{issue}_SESSION_STATE.md`, as seen in some other repos)
are not adopted here — see [isejalabs/homelab#1193](https://github.com/isejalabs/homelab/issues/1193)
for why and for the open question of what (if anything) should replace them.
