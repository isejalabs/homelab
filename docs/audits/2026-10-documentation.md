# Documentation Audit — October 2026

**Date:** 2026-10-12. **Status:** Assessment complete; five follow-up issues grouped beneath #1608, under #1336. **Scope:** Current documentation structure, readability, operational and recovery usefulness, consistency with repository configuration, and public disclosure. **Origin:** Read-only review of the local `main` checkout and public repository. **Tracking:** Related to the open [Documentation improvement journey](https://github.com/isejalabs/homelab/issues/1336); this audit identifies residual findings after the September 2026 audit and its phase work.

## Summary

The repository has a strong documentation system: cross-cutting architecture, current-state reference, operational procedures, decisions, and dated audits have distinct roles; implementation-specific guidance is usually colocated; and several runbooks distinguish verified behavior from assumptions. Much of the September audit's structural direction is now present, including a root orientation page, an architecture overview, an index, an inventory, and operational/recovery guides.

The main remaining concerns are accuracy across entry points, the boundary between documented recovery and the broad rebuild claim, the intentional disclosure of home infrastructure details in a public repository, and the ease of finding and verifying high-impact procedures.

## Findings and recommended actions

### F1 — CI descriptions disagree across documentation

**Priority:** High. The root [README](../../README.md#staying-current) says there is no GitHub Actions CI. The repository contains eleven workflow files. The [CI guide](../architecture/ci.md) and [AGENTS.md](../../AGENTS.md) describe CI, but their counts and wording should also be reconciled: the CI guide says nine workflows/checks while its inventory contains ten validation workflows plus the labeler workflow, and AGENTS.md gives both eleven and nine in different sections. These differences make it hard to know which checks gate changes.

**Recommendation:** Make the root README, CI guide, and contributor instructions agree on which workflows validate changes, which are required checks, and which are automation. Link to the CI guide rather than duplicating a workflow count unless that count is maintained from an authoritative source.

### F2 — Recovery boundaries qualify the broad rebuild claim

**Priority:** High. The root README says the whole stack can be rebuilt from the repository. The [disaster recovery guide](../backup/disaster-recovery.md) identifies root-zone DNS recovery as outside the repository and says its documented sequence has not been run as one timed rehearsal. The owner clarifies that the **cluster itself is recoverable** because apps and configuration live in Git, application data is backed up by kopiur, and cluster rebuilds are exercised in the `rebuild` environment on an irregular, roughly monthly cadence. The gap is broader homelab recovery: some components outside the cluster are incompletely documented, some are not fully backed up or recoverable, and secrets held in 1Password have no periodic backup. The guide's “not rehearsed end to end” statement should be reconciled with the recurring rebuild exercises so it describes precisely what has and has not been exercised.

**Recommendation:** Preserve the distinction between cluster recovery and whole-homelab recovery. Document the existing `rebuild` exercise cadence and validation, then identify external components, required records/access, backup coverage, and restore procedures that remain incomplete. Explicitly assess recovery of 1Password-held secrets and establish a periodic backup or document the accepted recovery gap. Align the README and disaster recovery guide with the verified cluster recovery capability and the remaining out-of-cluster limitations.

### F3 — Public disclosure of infrastructure details should be an explicit choice

**Priority:** Medium. The public docs contain real internal domains, IP addresses, hostnames, service relationships, and detailed administrative procedures. This can be useful for reproducibility and is not itself evidence of a credential leak, but the combined inventory reveals meaningful details about a home network.

**Recommendation:** Review the public documentation as a whole and record a disclosure policy: which details are intentionally public, which should be generalized, and which belong in private records. Handle any confirmed credential exposure through the appropriate response and rotation process.

### F4 — Navigation can be more task-oriented

**Priority:** Medium. The [documentation index](../README.md) explains the taxonomy and where documents belong, and the root README gives a good architecture path. Readers responding to an incident or performing maintenance still need to infer which path to follow across multiple indexes.

**Recommendation:** Add a compact “I need to…” route from the landing pages for bootstrap, troubleshooting, upgrade, restore, and full recovery. Keep the procedures in their owning documents and use links rather than copying instructions.

### F5 — Long guides can better support quick scanning

**Priority:** Medium. Some guides combine conceptual explanations, routine procedures, and detailed edge cases in substantial documents, including the Terragrunt README, network architecture, and backup/restore guide. Their detail is valuable, but readers may need a quicker path to the common action.

**Recommendation:** Review the longest operational guides for a brief common-task path, useful contents links, and clearer separation of routine steps from exceptional cases. Split a guide only when it serves distinct tasks that are hard to scan together.

### F6 — Verification and sources of truth should be visible for high-impact procedures

**Priority:** Medium. The recovery guide usefully labels tested and untested paths, and the workload catalog explains which fields derive from repository configuration. These are good patterns to apply selectively to other procedures where stale instructions can cause data loss or a long outage.

**Recommendation:** Identify the highest-impact runbooks and record what was last exercised, the result, and where volatile facts come from. Link to authoritative configuration instead of repeating values when that improves maintainability. Avoid adding review overhead to every document.

## Relationship to the September 2026 audit

The September audit's recommendations to establish documentation categories, create an architecture overview, improve orientation, and add operational and recovery guidance are substantially reflected in the current repository. Its assessment should remain an immutable historical snapshot; this audit records the current residual findings instead of rewriting it. The existing [umbrella issue #1336](https://github.com/isejalabs/homelab/issues/1336) remains open, while its four phase issues are closed. These residual findings are grouped in the intermediate [Documentation audit follow-ups — October 2026](https://github.com/isejalabs/homelab/issues/1608) issue beneath #1336.

## Proposed follow-up issues

The following five focused follow-ups were created as native sub-issues of [Documentation audit follow-ups — October 2026](https://github.com/isejalabs/homelab/issues/1608), which is itself a sub-issue of the existing [Documentation improvement journey](https://github.com/isejalabs/homelab/issues/1336):

1. [#1599 — Reconcile CI claims and workflow counts](https://github.com/isejalabs/homelab/issues/1599).
2. [#1600 — Clarify and close whole-homelab recovery gaps](https://github.com/isejalabs/homelab/issues/1600).
3. [#1601 — Review public disclosure of homelab details](https://github.com/isejalabs/homelab/issues/1601).
4. [#1602 — Improve task-first navigation and scanning](https://github.com/isejalabs/homelab/issues/1602).
5. [#1603 — Record verification for high-impact runbooks](https://github.com/isejalabs/homelab/issues/1603).

## Review method and limits

This was a read-only review of the local checkout and public repository presentation. It did not test procedures against live infrastructure, verify all external links, or perform a security assessment of the network. The public-disclosure finding is a prompt for an owner decision, not a claim that the published details are exploitable.
