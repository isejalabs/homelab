---
status: current
---

# Project board statuses

Work across the `isejalabs` repos is steered on two org projects that share one `Status` vocabulary: [homelab](https://github.com/orgs/isejalabs/projects/1) and [terraform-proxmox-talos](https://github.com/orgs/isejalabs/projects/2). See [`architecture/repositories.md`](../architecture/repositories.md#where-issues-live) for which repo an issue belongs in.

## Statuses

| Status | Applies when | Typical way in |
| --- | --- | --- |
| Backlog | Captured, but not triaged or not planned soon | Issue auto-added to the project |
| Ready | Triaged, scope is clear, nothing blocks it; next to pick up. No work started, no PR yet | Manual, after triage; or an issue is reopened |
| In progress | Someone is working on it: a branch exists or a (draft) PR is linked | PR linked to the issue; or review changes requested |
| In review | The PR is ready for review, or approved and waiting to merge | Review approved; or manual when a draft PR is marked ready for review |
| Done | Merged and closed | PR merged, or issue closed |

"Ready" means *ready to start*, not *ready to close*. The "ready to merge" state is **In review**.

## Workflow mapping

These are the project's built-in workflows (Project → Workflows). The mapping must be identical in both projects.

| Workflow | Sets status |
| --- | --- |
| Auto-add to project / Auto-add sub-issues to project | Backlog (the project default; no status set is needed) |
| Pull request linked to issue | In progress |
| Code changes requested | In progress |
| Code review approved | In review |
| Pull request merged | Done |
| Item closed / Auto-close issue | Done |
| Item reopened | Ready |

PRs are opened as drafts by default, so a linked PR means work is under way. GitHub has no workflow for "marked ready for review"; move the item to In review by hand at that point.

## Other fields

Both projects can carry the optional `Priority` (P0–P2) and `Size` (XS–XL) fields; the homelab "Prioritized backlog" view groups by Priority.
