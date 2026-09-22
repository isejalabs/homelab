# Documentation Audit — September 2026

> **Status:** Audit
> **Date:** 2026-09-22
> **Scope:** Repository documentation, information architecture, readability, maintainability, operational usefulness and homelab documentation practices
> **Repository:** `isejalabs/homelab`

## 1. Purpose

This document records an assessment of the homelab repository's documentation as of September 2026.

The purpose of the audit is to:

* assess the current documentation structure and quality;
* identify gaps and sources of documentation friction;
* establish principles for future documentation work;
* provide a durable reference for follow-up work;
* distinguish documentation improvements from implementation changes.

This document is a **point-in-time assessment**. It does not itself represent the current system architecture and should not be treated as authoritative configuration.

The repository configuration and code remain the source of truth for implementation details.

---

## 2. Executive summary

The repository already has a strong documentation foundation, particularly for architectural concepts, environments, workloads and Kustomize conventions.

The documentation demonstrates several good practices:

* documentation is generally colocated with the implementation it describes;
* cross-cutting architectural documentation is separated into `docs/`;
* architectural reasoning is documented rather than merely listing configuration;
* environments and workloads are explicitly described;
* historical material is retained separately;
* implementation-specific README files provide local context.

The main opportunity is therefore **not simply to add more documentation**.

The larger opportunity is to improve the **information architecture and separation of documentation purposes**.

Currently, architecture, reference information, procedures, operational guidance and historical material are partly intermingled. This makes the repository good at explaining how the system is constructed, but less effective at answering operational questions such as:

> How do I change this?

> How do I troubleshoot this?

> How do I recover this?

> What is the authoritative source for this value?

The recommended direction is to organize documentation around five distinct questions:

| Documentation type    | Primary question                        |
| --------------------- | --------------------------------------- |
| Overview              | What is this system?                    |
| Architecture          | Why is it designed this way?            |
| Reference             | What currently exists?                  |
| Procedures / runbooks | How do I change, operate or recover it? |
| Decisions / history   | Why did it become this way?             |

The existing principle that implementation-specific documentation should remain close to the implementation should be retained.

---

## 3. Current strengths

### 3.1 Documentation ownership is already well defined

The repository distinguishes between cross-cutting documentation under `docs/` and subsystem-specific documentation located alongside implementation.

This is a strong pattern because it reduces the risk that a central documentation tree becomes a second, manually maintained representation of the repository.

### Recommendation

Retain and formalize this principle:

> **`docs/` describes the system as a whole; local README files describe the implementation they belong to.**

---

### 3.2 Architecture is documented rather than only configuration

The repository contains documentation explaining architectural relationships and design conventions rather than merely documenting directory structures.

The Kustomize documentation is a good example: it explains the relationship between bases, environments and Flux rather than only describing individual files.

This should remain a guiding principle.

---

### 3.3 Environment documentation provides valuable institutional knowledge

The environment documentation captures important information about the environment model, including workload selection, resource sizing, update behaviour and environment-specific infrastructure values.

This represents valuable institutional knowledge that would otherwise be difficult to reconstruct.

The main issue is not the amount of information but its presentation: conceptual information and low-level reference values are currently presented at similar levels.

---

### 3.4 Workload inventory is a strong foundation

The workload documentation provides a useful inventory of what is deployed and how workloads relate to the environment and deployment model.

This can be extended into a more human-oriented service catalogue without replacing the existing implementation-oriented inventory.

---

### 3.5 Historical information is retained

The repository documents significant architectural evolution rather than presenting the current architecture as if it had always existed in its present form.

This is particularly useful for a homelab because future changes often depend on understanding why previous approaches were replaced.

Historical material should remain available, but should be clearly distinguished from current architecture.

---

## 4. Main findings

### F1 — Documentation purposes are not yet sufficiently separated

**Priority:** High

The repository contains several different types of information:

* architecture;
* implementation reference;
* operational procedures;
* troubleshooting;
* historical information;
* future/planned ideas.

These are not always clearly separated.

This increases the cognitive load for readers because the expected use of a document is not always immediately apparent.

### Recommendation

Establish an explicit documentation taxonomy:

```text
docs/
├── architecture/
├── reference/
├── operations/
├── procedures/
├── decisions/
├── audits/
└── history/
```

This should be treated as a conceptual model rather than a requirement to move every existing document immediately.

Implementation-specific documentation should remain alongside its implementation.

---

### F2 — The root README should prioritize orientation

**Priority:** High

The root README contains useful technical information but currently requires the reader to understand a number of infrastructure concepts before obtaining a complete mental model.

The README should answer the following within approximately one minute:

1. What is this repository?
2. What technologies make up the system?
3. What does the architecture look like?
4. What environments exist?
5. Where should I continue reading?

### Recommendation

Introduce an "At a glance" section containing:

* purpose;
* architecture diagram;
* technology stack;
* environment summary;
* documentation entry points.

The README should act primarily as an orientation and navigation page rather than as a comprehensive technical reference.

---

### F3 — The documentation needs an architecture overview

**Priority:** High

The current documentation contains enough information to reconstruct the architecture, but the reader must infer several relationships from multiple documents.

### Recommendation

Add a concise architecture overview containing at least:

```text
Proxmox
   ↓
Talos Linux
   ↓
Kubernetes
   ↓
Cilium / networking
   ↓
GitOps / workloads
```

and the relevant relationships between:

* infrastructure provisioning;
* Talos;
* Kubernetes;
* networking;
* storage;
* secrets;
* Flux;
* workloads.

A diagram should complement, not replace, the existing written architecture documentation.

---

### F4 — Environment documentation mixes conceptual and reference information

**Priority:** Medium

The environment documentation contains valuable details but combines:

* the purpose of each environment;
* architectural conventions;
* generated or derivable infrastructure values;
* implementation mechanics;
* inferred reasoning.

This makes the document more difficult to scan.

### Recommendation

Start with a simple environment matrix:

| Environment | Purpose                   | Workload profile | Lifecycle    |
| ----------- | ------------------------- | ---------------- | ------------ |
| `prod`      | Production workloads      | Full             | Persistent   |
| `qa`        | Validation                | Full             | Persistent   |
| `dev`       | Development               | Reduced          | Persistent   |
| `head`      | Experimental/current      | Full             | Experimental |
| `poc`       | Proof of concept          | Reduced          | Disposable   |
| `rebuild`   | Rebuild/recovery          | Full             | Disposable   |
| `src`       | Source/module development | Reduced          | Disposable   |
| `dbg`       | Diagnostics               | Reduced          | Disposable   |

The exact values should be verified against the current repository before publication.

Detailed technical values should then be separated into reference material.

---

### F5 — Volatile reference information should not be manually duplicated unnecessarily

**Priority:** Medium

Values such as:

* VM IDs;
* IP pools;
* BGP ASNs;
* API VIPs;
* environment-specific parameters;
* versions;

may be derivable from the repository configuration.

Manually maintaining the same information in documentation creates a potential source of drift.

### Recommendation

Consider generating volatile reference tables from the authoritative configuration.

Generated documentation should clearly indicate its source, for example:

```text
<!-- Generated from repository configuration. Do not edit manually. -->
```

Conceptual documentation should explain the model; generated documentation should provide the current values.

---

### F6 — Operational documentation is less developed than architectural documentation

**Priority:** High

The repository provides substantial information about how the system is constructed.

There is less emphasis on how the system is operated during normal operation or failure.

Important operational questions should have explicit answers:

* How is an application added?
* How is an application updated?
* How is Kubernetes upgraded?
* How is Talos upgraded?
* How is a node replaced?
* How is Flux troubleshooting performed?
* How is DNS troubleshooting performed?
* How is storage troubleshooting performed?
* How is a backup restored?
* How is a cluster rebuilt?

### Recommendation

Introduce an operational documentation layer containing procedures and runbooks.

---

### F7 — Disaster recovery should be documented explicitly

**Priority:** High

The repository has infrastructure and rebuild concepts that provide a good foundation for disaster recovery documentation.

However, the complete recovery chain should be explicitly documented.

The documentation should answer:

> Can the homelab be rebuilt if the Kubernetes cluster is completely lost?

and:

> What happens if the infrastructure host, persistent data, secrets, DNS or GitOps controller is unavailable?

### Recommendation

Add a disaster recovery document describing:

* recovery scenarios;
* dependencies;
* backups;
* restore mechanisms;
* manual steps;
* expected recovery order;
* recovery limitations;
* RPO/RTO where meaningful;
* date and result of recovery tests.

A particularly useful distinction is between:

> **automated recovery**

and

> **manual recovery**

---

### F8 — Backup documentation should emphasize restore capability

**Priority:** High

Backup documentation should not only establish that backups exist.

It should establish:

* what is backed up;
* where it is stored;
* how frequently;
* retention;
* dependencies;
* how it is restored;
* whether restoration has actually been tested.

A useful reference format is:

| Data                        | Backup                   | Frequency            | Retention            | Location       | Restore tested |
| --------------------------- | ------------------------ | -------------------- | -------------------- | -------------- | -------------- |
| Kubernetes configuration    | Git                      | Continuous           | Git history          | Remote Git     | N/A            |
| Persistent application data | Backup system            | Defined per workload | Defined per workload | Backup storage | Yes/No         |
| Infrastructure state        | Repository/backend       | Defined              | Defined              | ...            | Yes/No         |
| Secrets                     | Secret-management system | Defined              | Defined              | ...            | Yes/No         |

Exact values should be populated from the repository and actual infrastructure.

---

### F9 — A human-oriented service catalogue would complement the workload inventory

**Priority:** Medium

The workload inventory is useful for infrastructure understanding.

Operationally, however, it is also useful to know what a service does and what it depends on.

### Recommendation

Add or extend a service catalogue with information such as:

| Service   | Purpose | Environment | Data | Backup | Dependencies |
| --------- | ------- | ----------- | ---- | ------ | ------------ |
| Service A | ...     | ...         | ...  | ...    | ...          |

Avoid unnecessarily duplicating configuration that can be obtained directly from the repository.

---

### F10 — Service dependencies should be made explicit

**Priority:** Medium

Some dependencies are currently distributed across multiple documents and configuration files.

During an outage, it is useful to understand relationships such as:

```text
GitHub
  ↓
Flux
  ↓
Kubernetes
  ├── Cilium
  ├── Storage
  ├── Secrets
  └── Applications
```

### Recommendation

Document dependencies for critical infrastructure and services.

For important services, distinguish:

* runtime dependencies;
* deployment dependencies;
* external dependencies;
* recovery dependencies.

This distinction is important because a service may continue operating even when its deployment mechanism is unavailable.

---

### F11 — Documentation should identify the source of truth

**Priority:** Medium

The GitOps architecture makes authoritative sources particularly important.

For each class of information, readers should be able to determine where the authoritative value lives.

Example:

| Information            | Source of truth               |
| ---------------------- | ----------------------------- |
| VM definition          | Infrastructure configuration  |
| Kubernetes version     | Infrastructure/configuration  |
| Environment definition | Environment configuration     |
| Application deployment | Kubernetes/Flux configuration |
| Secret declaration     | Git                           |
| Secret value           | Secret-management system      |
| Backup policy          | Backup configuration          |

### Recommendation

Introduce a source-of-truth convention and use it consistently.

---

### F12 — Architecture decisions should be separated from current-state documentation

**Priority:** Medium

Some documentation inevitably contains reasoning about why the repository is structured in a particular way.

This information is valuable, but architectural decisions should not become mixed into reference documentation.

### Recommendation

Introduce lightweight Architecture Decision Records (ADRs).

Potential initial ADRs include:

* Proxmox + Talos architecture;
* environment model;
* Kustomize structure;
* Flux adoption;
* storage strategy;
* secrets strategy.

Recommended structure:

```text
docs/decisions/
├── README.md
├── 001-...
├── 002-...
└── ...
```

Each ADR should minimally contain:

```markdown
# Decision

## Status

## Context

## Options considered

## Decision

## Consequences
```

---

### F13 — Inferred information should be explicitly distinguished from authoritative information

**Priority:** Medium

Some documentation may contain interpretations of repository behaviour where explicit design intent is not documented.

This is useful during an audit but should not silently become architectural truth.

### Recommendation

Use explicit status language:

```text
Status: current
Status: planning
Status: historical
Status: inferred
Status: audit
```

If a design decision is important and currently undocumented, prefer creating an ADR rather than embedding an inference into architecture documentation.

---

### F14 — Historical material should be clearly marked

**Priority:** Low

Historical material is useful but can be mistaken for current system truth by humans and automated tools.

### Recommendation

Clearly identify historical directories and documents as non-authoritative.

The `_attic` concept is useful and should remain, with an explicit statement that material there is not part of the active implementation.

---

### F15 — Naming conventions could be standardized

**Priority:** Low

Documentation filenames should use a consistent convention.

### Recommendation

Prefer:

```text
lowercase-kebab-case.md
```

For example:

```text
update-handling.md
```

instead of filenames containing spaces.

This also makes command-line use and automation simpler.

---

## 5. Proposed documentation model

The following model is recommended:

```text
docs/
├── README.md
│
├── architecture/
│   ├── overview.md
│   ├── network.md
│   ├── storage.md
│   ├── secrets.md
│   ├── environments.md
│   ├── workloads.md
│   └── kustomize.md
│
├── reference/
│   ├── services.md
│   ├── environment-reference.md
│   └── ...
│
├── operations/
│   ├── day-to-day.md
│   ├── updates.md
│   ├── backups.md
│   ├── disaster-recovery.md
│   └── troubleshooting.md
│
├── procedures/
│   ├── bootstrap.md
│   ├── rebuild.md
│   ├── add-application.md
│   ├── upgrade-kubernetes.md
│   ├── upgrade-talos.md
│   └── ...
│
├── decisions/
│   ├── README.md
│   └── ADR-*.md
│
├── audits/
│   └── 2026-09-documentation.md
│
└── history/
```

This is a target model, not a requirement for immediate restructuring.

Existing subsystem-specific README files should remain next to their implementation where that provides better locality.

---

## 6. Documentation principles

The following principles should guide future documentation changes.

### 6.1 Code and configuration remain authoritative

Documentation should explain the system without becoming a second source of configuration truth.

### 6.2 Explain why, not generic technology

Documentation should explain how a technology is used **in this repository**, rather than reproducing generic Kubernetes, Flux, Kustomize or Proxmox documentation.

### 6.3 Prefer navigation over duplication

Readers should be directed to the authoritative document rather than presented with duplicated information.

### 6.4 Separate current truth from planning

Future architecture must not be confused with the current implementation.

### 6.5 Make operational knowledge explicit

If successful operation depends on knowledge that currently exists only in the maintainer's memory, it should be considered a documentation gap.

### 6.6 Document recovery, not only deployment

A homelab is not fully documented if it can be deployed but not reliably restored.

### 6.7 Prefer generated reference information where practical

If a value can be reliably derived from source configuration, consider generating the documentation rather than maintaining it manually.

### 6.8 Record important decisions

When an architectural choice is non-obvious and likely to be revisited, document the decision and its rationale.

---

## 7. Recommended follow-up

The audit should be converted into implementation work rather than becoming a second issue tracker.

Recommended sequence:

### Phase 1 — Navigation and orientation

1. Improve root README.
2. Improve `docs/README.md`.
3. Add a concise architecture overview.
4. Add an architecture diagram.
5. Establish documentation status conventions.

### Phase 2 — Operations

1. Add operational documentation.
2. Add troubleshooting/runbooks.
3. Add disaster recovery documentation.
4. Improve backup/restore documentation.
5. Document common upgrade and replacement procedures.

### Phase 3 — Reference

1. Improve workload/service catalogue.
2. Document dependencies.
3. Identify sources of truth.
4. Separate conceptual environment documentation from volatile reference data.
5. Investigate generated reference documentation.

### Phase 4 — Architectural history

1. Introduce ADR conventions.
2. Record important existing architectural decisions.
3. Move future/planning material into clearly labelled planning documents where appropriate.

---

## 8. Suggested GitHub issue structure

The audit should remain a historical assessment.

Implementation should be tracked separately in GitHub issues.

A suitable umbrella issue would be:

**Documentation: improve structure and operational usability**

Suggested work items:

* [ ] Improve root README and documentation landing page
* [ ] Add architecture overview and diagram
* [ ] Define documentation taxonomy
* [ ] Establish document status conventions
* [ ] Add operational runbooks
* [ ] Add disaster recovery documentation
* [ ] Improve backup/restore documentation
* [ ] Add service catalogue
* [ ] Document critical dependencies
* [ ] Document sources of truth
* [ ] Introduce ADR structure
* [ ] Investigate generated reference documentation

Individual issues should be created where an item is large enough to require independent discussion or implementation.

---

## 9. Success criteria

The documentation improvement should be considered successful when a new maintainer can:

### Orientation

* understand the overall architecture within a few minutes;
* identify the major infrastructure layers;
* understand the purpose of each environment;
* find the relevant documentation without searching the entire repository.

### Operations

* perform common updates using documented procedures;
* diagnose common failures using runbooks;
* identify dependencies when a service fails;
* identify authoritative configuration sources.

### Recovery

* understand what is backed up;
* determine how data can be restored;
* understand the cluster rebuild process;
* identify manual recovery steps;
* distinguish tested recovery procedures from theoretical ones.

### Maintenance

* understand why major architectural decisions were made;
* identify which documents describe current truth;
* distinguish historical and future/planning material;
* avoid modifying generated or derived documentation manually.

---

## 10. Conclusion

The repository already has a strong foundation for serious homelab documentation.

The principal opportunity is not to document every component in greater detail. It is to make the existing knowledge easier to navigate, distinguish and operate.

The desired progression is:

```text
Current:

Architecture
Reference
Procedures
History
Planning
    │
    └── partially mixed


Target:

             Documentation
                   │
       ┌───────────┼───────────┐
       │           │           │
   Understand    Operate     Change
       │           │           │
 Architecture   Runbooks   Procedures
 Reference      Recovery   Local README
       │
   Decisions
       │
    History
```

The guiding principle should be:

> **Architecture explains why.
> Reference explains what.
> Procedures explain how.
> Runbooks explain how to recover.
> ADRs explain decisions.
> History explains change.
> Code and configuration remain authoritative.**

This audit should remain unchanged as a historical snapshot. Follow-up work should be tracked through GitHub issues and pull requests, with subsequent audits used to assess progress.
