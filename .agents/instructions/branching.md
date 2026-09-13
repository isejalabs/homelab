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

## Why not per-issue local state files

Some other repos (e.g. [bpg/terraform-provider-proxmox's `CLAUDE.md`](https://github.com/bpg/terraform-provider-proxmox/blob/main/CLAUDE.md))
keep a `.dev/{issue}_SESSION_STATE.md`-style scratch file per issue to carry context across sessions.
This repo doesn't (yet) adopt that: sessions here typically run in an ephemeral cloud container that's
reclaimed between pauses — sometimes after only minutes — so a file that only exists in that container
wouldn't survive being picked back up later. It would need to be committed to survive, which defeats
the point of keeping session-scratch content out of the actual change. Revisit this if/when there's a
place for such state that does survive (e.g. the issue body itself, or PR description checklists per
the PR discipline section).
