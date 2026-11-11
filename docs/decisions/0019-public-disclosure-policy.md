---
id: ADR 0019
status: planning
accepted: 2026-11-11
becomes-current: once the file sweep (https://github.com/isejalabs/homelab/issues/2284) and the tracker sweep (https://github.com/isejalabs/homelab/issues/2285) are done
---

# Public disclosure of homelab details

## Context

The repository is public on purpose: other people doing home-ops are meant to be able to read it, reuse it and learn from it. That only works if the configuration, versions, topology and procedures are published, so a policy cannot be "publish less" across the board. The [October 2026 documentation audit](../audits/2026-10-documentation.md#f3--public-disclosure-of-infrastructure-details-should-be-an-explicit-choice) found that this was never a deliberate choice, and [#1601](https://github.com/isejalabs/homelab/issues/1601) asked for one.

What the policy has to protect is privacy, not secrecy. The whole software stack, its versions and its configuration are in Git, so a reader of the documentation learns very little a reader of the manifests would not. What the documentation can add on top is details that identify or locate the owner or the household, or that feed spam and social engineering. Credentials are a separate matter and stay under the secrets process ([ADR 0010](0010-sops-vs-sealed-secrets-vs-1password-eso.md), [`secrets.md`](../architecture/secrets.md)).

Four facts bound the options:

- Some of that material is already published. Commits cannot be changed (history stays as it is), and the commit author, the organization name and the project domain already tie the repository to its owner. Anonymity is therefore not achievable and not a goal.
- Documentation must match the code. Manifests and Terragrunt need the real values, so generalizing them in the documentation only creates drift.
- Anything in GitHub other than a commit can still be edited: issue and pull request bodies, comments, release notes. Editing them reduces what is found in future; it does not undo what was seen.
- The documentation is also published as a searchable site (see [`docs/README.md`](../README.md#documentation-site)), which makes whatever the documentation says easier to find.

## Options considered

- **Status quo.** Publish everything, with no rule. Cheap, but it leaves the choice implicit and gives contributors and agents nothing to apply when they write the next document.
- **Generalize everything, structure included.** Placeholders for every domain, address range and hostname. It costs the reproducibility the repository exists for, creates permanent drift between documentation and code, and gains little, because the manifests keep the real values.
- **Publish a sanitized mirror and keep the real repository private.** Defeats the purpose (others consuming the repository) and doubles the maintenance.
- **Rewrite history to remove what was published.** Rejected by the owner. It breaks forks and references, and GitHub keeps pull request refs and cached views regardless, so the result would still not be a clean removal (see Consequences).
- **A tiered policy that classifies a detail by what it lets a reader do.** Chosen.

## Decision

A detail is classified by what it enables: **understanding and reproducing the setup** (public), or **identifying, locating or contacting a person** (not public). Where it is hard to tell, the detail is treated as the more restrictive class. The policy applies to everything written in this repository and about it: documentation, comments, issue and pull request descriptions, comments and reviews, commit messages and release notes.

### 1. Public on purpose

- The stack, versions, configuration and the way the pieces relate.
- Hostnames, internal domains and service relationships under the project's own domain, and the project and organization names.
- The structural network values that the code needs: private address ranges and VLAN IDs. They are not routable from outside and the manifests contain them.
- Procedures, including administrative ones.
- Hardware described by what a reader needs to reproduce the setup (class of machine, CPU generation, memory, NIC speed, kinds of device and the protocols they speak). A model is named only where it decides compatibility or behavior that the documentation depends on.

### 2. Generalized, using a placeholder convention

- Account names of people: neutral placeholder first names for adults (`alice`, `bob`, `adam`, …). A person who needs a distinct account in a worked example gets one more placeholder from the same list.
- Household members who are not the owner: never named, never counted and never distinguished. Documentation says "a household account" or "another user". A convention such as `member-1`, `member-2` is not used, because the numbering itself states how many there are.
- Domains in examples that do not need the real one: `example.com`.

### 3. Never in the repository, the tracker or the documentation site

- A postal address, or any location finer than the country, and anything that shows when the owner is away.
- Personal email addresses and phone numbers.
- Serial numbers, MAC addresses, licence keys, device and account identifiers.
- Public IP addresses, and ISP, customer or contract numbers.
- Real names of household members, and any statement about the composition of the household.
- Screenshots, photographs and exports containing any of the above, including metadata.
- The private list used to enforce this policy (see below).

A contact address that has to exist in configuration (a certificate-authority account, an alert sender) is a dedicated alias created for that purpose, never a personal mailbox.

### Private records and enforcement

What stays out of the repository is kept in the owner's 1Password vault or another private place, never in a repository file. The policy and the documents about it describe categories, never instances.

Compliance is checked by the guard from [#2286](https://github.com/isejalabs/homelab/issues/2286): pattern classes (email addresses, MAC addresses, serial-like strings, public IP literals) run in CI and are public, while a list of specific strings stays outside the repository and is read by a local hook. A deny-list of specific strings is never committed, since it would publish exactly what it forbids.

### When something slips through

1. Fix the file in a pull request.
2. Edit the issue, pull request or comment that carries it, and delete the revision from its edit history.
3. Replace what can be replaced (an alias, a token, an account).
4. Treat commits as permanent and do not rewrite history.
5. Credentials follow the secrets process, not this one.

## Consequences

- Contributors and agents have a rule to apply before writing, and a defined way to react afterwards.
- Reproducibility stays intact, because the policy leaves the structure and configuration public and only the personal layer changes.
- The residual exposure is explicit. Commit history, the commit author, forks, archives, search-engine caches and GitHub's own cached views and pull request refs stay out of reach of this policy. Pull request refs and cached views can only be removed by GitHub Support, which dereferences or deletes the pull request. Dereferencing keeps the body and comments, and editing a body does not remove what a retained diff shows ([GitHub: removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
- Edit history of comments can be removed by their author and by anyone with write access (the revision's content goes, its author and time stay); the documentation does not say the same for issue and pull request descriptions, so that is tested on a throwaway item first ([GitHub: tracking changes in a comment](https://docs.github.com/en/communities/moderating-comments-and-conversations/tracking-changes-in-a-comment)).
- Placeholders cost a reader a small translation, and the guard will produce occasional false positives.
- The documentation site is already published and indexable, so the sweeps ([#2284](https://github.com/isejalabs/homelab/issues/2284), [#2285](https://github.com/isejalabs/homelab/issues/2285)) reduce what a search engine shows only after the next build and re-crawl.

## Amendments

Amended on 2026-11-11 at the owner's request ([#2284](https://github.com/isejalabs/homelab/issues/2284)):

- The owner's accounts map to fixed placeholders: `bob` for the personal account and `bob-adm` for the administrative one. Documentation shows the placeholder where a real account name would appear, so a reader substitutes their own. The second adult account that appears in worked examples is `alice`; the household rule above is otherwise unchanged, so no further names, no counts and no statement about relationships.
- The AWS account ID of the Terraform state backend stays public. The tooling needs it in `terragrunt/*/account.hcl` and the per-environment `.envrc` files, so moving it into a SOPS file would not remove it from the repository. The owner accepts the disclosure for now and will reconsider if a separate production AWS account is created.
