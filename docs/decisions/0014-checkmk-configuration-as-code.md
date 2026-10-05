# Checkmk configuration as code: Terraform provider, Ansible deferred

## Status

planning

## Context

Checkmk (the `prod` site on `monitoring2`, 2.4 Raw edition) is configured through its web UI today. That was acceptable while the configuration was small, but the RustFS capacity monitoring ([#1438](https://github.com/isejalabs/homelab/issues/1438)) adds a repeatable set of objects: one Password Store entry per RustFS monitoring identity (up to one per environment, `<env>-checkmk-monitoring`), a host for the RustFS itself, a special-agent rule that references the stored passwords, and an activation of the changes. [ADR 0003](0003-repository-and-tool-boundaries.md) left open whether Checkmk host, password-store and rule setup stays manual or becomes code, and the tool-boundary rule there sends objects behind an API with a lifecycle to Terraform, while files on a long-lived host (such as the plugin files on `monitoring2`) go to Salt.

This ADR records the options reviewed (October 2026, from documentation and source only; nothing was tested against a Checkmk site yet) and the resulting choice, so the reasoning survives if the choice is revisited.

## Options considered

- **Manual, documented (status quo).** No new tooling and no risk to the Checkmk site, but nothing is reviewable or reproducible, and a rebuilt site loses the configuration. Fine for a handful of objects, poor for a growing per-environment set.
- **Terraform/OpenTofu via the community provider [`BlackMesaLTD/checkmk`](https://github.com/BlackMesaLTD/terraform-provider-checkmk).** Uses the Checkmk REST API and supports Checkmk 2.2 to 2.4. Resources cover what is needed here: `checkmk_password`, `checkmk_folder`, `checkmk_host`, a generic `checkmk_rule`, and `checkmk_activation`. Fits the existing toolchain (Terragrunt, OpenTofu, 1Password provider, the `terraform-modules` repo). Weaknesses: a single-maintainer project with few users (latest release v0.0.5 on 2026-06-17, while its README example pins `~> 0.1`, which has to be reconciled), partial API coverage, no data sources, single-site only, and complex rule values may need JSON encoding. The password value is write-only towards the API but, like other Terraform-managed secrets, is held in Terraform state. An older provider from 2020 exists but is abandoned.
- **Ansible with the official [`checkmk.general`](https://github.com/Checkmk/ansible-collection-checkmk.general) collection.** The most mature option: maintained under the Checkmk organisation, v8.5.1 with activity in October 2026, 20 modules including `password`, `folder`, `host`, `rule`, `discovery` and `activation`, plus about 25 lookup plugins, and a community far larger than the Terraform provider's. Provided as is, without commercial support. Rules take a version-specific `value_raw`, and a rule cannot carry a secret inline, so secrets must live in the Password Store and be referenced, which is also the intended design here. Its cost is adopting a second configuration tool: Salt vs Ansible is a separate, unresolved assessment, and the owner judged adopting Ansible too complex for now.
- **Salt.** No Checkmk module was found; the REST API could be called through generic HTTP states, which works but reproduces what the other tools provide. Salt remains the right tool for the files on `monitoring2` (the custom special agent and check plugin), which is a different concern from the API objects.

## Decision

Use Terraform (OpenTofu through Terragrunt, with the module in `isejalabs/terraform-modules`) for the Checkmk API objects needed by the RustFS monitoring. Ansible is deliberately set aside for now because of its added complexity at the moment, not because it is unsuitable; the `checkmk.general` collection is the documented fallback and the likely successor if the Terraform provider proves too immature. Salt keeps delivering plugin files to `monitoring2`, as decided in ADR 0003.

The decision stays `planning` until a spike against a throwaway Checkmk Raw 2.4 container confirms that the provider can create a password, a folder, a host, a rule for a built-in ruleset and a rule for a custom special-agent ruleset, and can activate the changes (tracked in [#1529](https://github.com/isejalabs/homelab/issues/1529)).

## Consequences

- The ADR 0003 open decision on Checkmk configuration is resolved in favour of code; objects not covered by the provider stay manual and documented rather than blocking the rest.
- Provider maturity is the main risk: pin the provider version exactly, and re-validate after provider and Checkmk upgrades. Rule values change between Checkmk versions (2.5 changes the password reference representation), so a Checkmk upgrade needs a deliberate check.
- Activation applies all pending changes, not only Terraform-managed ones, so unrelated pending UI edits would be activated by an apply. Prefer the provider's manual activation with an explicit activation resource, and avoid concurrent UI edits while applying.
- The Password Store obfuscates rather than encrypts, with its key in the same site directory (see the Checkmk documentation on the [password store](https://docs.checkmk.com/2.4.0/en/password_store.html)); site filesystem access stays trusted, and the secret must not appear on a command line (the plugin API accepts stdin for special agents, but how a stored secret reaches stdin is unverified and must be proven in the plugin).
- Checkmk is one site, while the identities are per environment, so where the units live is an open question: one shared unit, or per-environment units that each write their own entry into the shared site. This is the singleton-unit question of ADR 0003 for the first time with a real example.
- A rule for a custom special-agent ruleset needs the plugin loaded on the site first, so the plugin work (via Salt) gates the rule part of the implementation. Whether the REST API accepts such a rule in the Raw edition is unverified.
- If the Terraform route fails the spike, revisit this ADR: either keep the missing pieces manual, or revisit Ansible with the collection above.
