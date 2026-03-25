# Update Handling and Automerging of PRs

## Overview

### Toolchain

- **renovate**: A tool for automating dependency updates, which creates PRs for package updates. It not only creates PRs but also labels them and also automerges them based on the type of update and whether they should be automerged or not.
- **labeler**: A tool for automatically labeling PRs based on their content and the rules defined in the configuration. It is used to label PRs with the environment (e.g., `env:PROD`, `env:QA`) and the area a PR is affecting (e.g., `area:terraform`, `area:k8s`), which are then used by mergify to determine whether a PR should be automerged or not.
- **mergify**: A tool for automating the merging of PRs based on specific conditions. It is configured to automatically merge PRs created by renovate for certain types of updates and configuration changes, while excluding others based on labels.
- **argo-cd**: A tool for automating the deployment of applications to Kubernetes, following the **GitOps** approach. It is used to deploy changes to the k8s cluster based on what is defined in `git`, instead of a user applying the changes manually by, e.g., `kubectl apply`.

#### Labels

Github labels are used to categorize and manage PRs based on their content and the rules defined in the configuration. The relevant labels for update handling and automerging include:

- `pr-type:renovate`: Indicates that a PR was created by renovate for a package update – in contrast to manual PRs (which do _not_ have a `pr-type` label, e.g., `pr-type:manual`).
- `updateType:digest`, `updateType:pinDigest`, `updateType:patch`, `updateType:minor`, `updateType:major`: Indicate the type of update (e.g., digest update, patch update, minor update, etc.) for a package update PR created by renovate.
- `updateStrategy:manual`: Indicates that a PR is excluded from automerging and requires manual review and merging, e.g., for critical/terragrunt-managed packages or for changes that require manual handling and review.
- `updateStrategy:pinWatch`: Indicates that a package is _pinned_ to a specific version (in other environments) and the PR in question is used for _watching_ for new versions and updates. The `POC` environment is used for watching and is exempted from automerging (except for patches of the pinned version), while the `HEAD` environment will receive new versions through automerging.
- `env:PROD`, `env:QA`, `env:DEV`, etc.: Indicate the environment that a PR is affecting, which can be used to determine whether a PR should be automerged or not based on the environment it is affecting.
- `area:terraform`, `area:k8s`, etc.: Indicate the area that a PR is affecting, which can be used to determine whether a PR should be automerged or not based on the area it is affecting.

## Configuration changes

### K8S and argo-cd

Configuration changes for k8s packages are handled differently, based on the environment. For production and test environments, the manifest are applied by argo-cd. For development environments, the manifest are applied manually by a user. For other environments, also applicable for testing, it depends on the specific test scenario investigated,

#### argo-cd

- HEAD
- PROD
- QA
- REBUILD

#### manually

- DEV
- SRC

#### depends on test scenario

Depending on the test scenario, configuration changes for k8s packages might be applied manually by the user or by argo-cd. This is the case for environments used for testing, which are not production or test environments. Examples for manual handling might be, e.g., testing/investigating a specific application or its specific version, without requiring a full deployment. Examples for argo-cd handling might be testing a full deployment, besides the REBUILD environment, or investigating argo-cd features or issues.

- DBG
- POC

### terraform/terragrunt

Configuration changes for infrastructure packages managed by terraform/terragrunt are handled manually, as they require manual review of the changes/plan. There's no CI (continuous integration) for the core infrastrucure. Hence, PRs created by renovate for these packages are labeled with `updateStrategy:manual` to exclude them from automerging by renovate and mergify.

## Detecting package updates

### renovate

Package updates are handled by renovate, which creates PRs for updates to packages. These PRs are labeled with `pr-type:renovate` and specific labels indicating the type of update (e.g., `updateType:digest`, `updateType:patch`, `updateType:minor`). Renovate is also configured to automatically merge PRs for certain types of updates (e.g., `digest`, `pinDigest`, `patch`), while excluding critical/terragrunt-managed packages from automerging by labeling them with `updateStrategy:manual`.

Renovate is configured to create separate PRs for different environments (e.g. PROD, QA) and types of updates (`major`, `minor`, `patch`, incl. `separateMinorPatch=true`), which allows for more granular control over which updates are automerged and which require manual review or explicit testing before they are promoted.

## Merging PRs for package updates

### Automatic merging rules

Generally, automerging is configured only for PRs created by renovate (labeled `pr-type:renovate`, thus excluding PRs created in other ways, e.g. by a user).
More specifically, renovate is configured to automatically certain types of updates (e.g., `digest`, `pinDigest`, `patch`), while excluding critical/terragrunt-managed packages from automerging by labeling them with `updateStrategy:manual`. Mergify is configured to automatically merge PRs for the `HEAD` environment as well as updates of type `minor`, in the latter case unless they are excluded from auto-merging labeled `updateStrategy:manual`.

The conditions for automerging are as follows:

- **renovate**: Automerge small updates , except for critical/terragrunt-managed packages (labeled `updateStrategy:manual`, cf. below). The types of updates are:
  - `digest` (labeled `updateType:digest`)
  - `pinDigest` (labeled `updateType:pinDigest`), and
  - `patch` (labeled `updateType:patch`)
- **mergify**: Mergify is merging PRs on the following criterias:
  - `env:head`: Automerge PRs for `HEAD` environment (labeled `env:head`), regardless of the area (k8s, terraform/terragrunt, etc.) and also ignoring whether they are exluded from automerging. They need to be created by renovate (labelled `pr-type:renovate`), at least.
  - `updateType:minor`: Automerge PRs for updates of type `minor` (labeled `updateType:minor`), unless they are excluded from automerging (labeled `updateStrategy:manual`), if they change files in the `k8s/` folder.

### PR creation, checking and notification

#### Reducing PR noise

Automerging is configured as `automergeType=branch` in renovate, which means that renovate will automatically merge the branch created instead of creating a PR. However, this is currently not working as expected, and PRs are still being created instead of branches being merged directly. This issue needs to be investigated further to determine the cause and find a solution.

### Handling special apps and use cases

Some packages have a non-standard update strategy, e.g. by allowing only updates of type `patch` or by pinning them to a specific version or by not allowing updates at all. There's also an exception for the `HEAD` and `PoC` environments.

#### Special environments

##### HEAD environment

The `HEAD` environment is a special environment used for testing new application versions and updates as soon as they are available (like tracking `latest` or `edge` version). It is configured to automerge all updates regardless of the type of update (also ignoring manual updates and version pinning). This is done to ensure that the latest versions are being tested and to allow for early detection of potential issues with new application versions and updates.

##### POC environment

The `POC` environment is a testing environment for proof of concept (PoC) implementations and investigations. It is a "throw-away" environment, which means that it is not intended for long-term use and can be easily recreated if needed – unlike the `DEV` environment.

The `POC` environment also serves as testbed and reminder for new package versions and updates. As such, it is exempted from application pinning and allows renovate to create PRs for all types of updates. While all other environments are pinned to a specific version, the `POC` (and `HEAD`) environment(s) is not pinned to a specific version, which allows for testing of new versions and updates as soon as they are available. Other than the `HEAD` environment, new package versions and updates in the `POC` environment are not automerged – to have a PR around as "reminder" for a new minor or major version.

#### Non-standard update strategy

| Package                             | Update strategy    | Description                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cilium`                            | Pin previous minor, Manual | Pinned to the "oldstable" version, i.e. previous minor version (for `cilium` being `X.Y-1`, e.g. 1.18.x instead of 1.19.x). Only `patch` updates are allowed. This is done for extra stability, as `cilium` is a critical component of the cluster and updates of type `minor` might introduce new features which could cause issues (and are not needed for proper functioning). |
| `isejalabs/terraform-proxmox-talos` | Manual             | No updates are allowed, as this package is managed manually by running terragrunt (or terraform) after changing the version number.                                                                                                                                                                                                                                               |
| `kubernetes-sigs/gateway-api`       | Pin minor          | Pinned to a specific minor version in accordance with other application compatibility constraints (`cilium`). Only `patch` updates are allowed.                                                                                                                                                                                                                                   |
| `kubernetes/kubernetes`             | Pin minor, Manual  | Pinned to a specific minor version in accordance with other application compatibility constraints (e.g. `checkmk`). Only `patch` updates are allowed.<br><br>No updates are allowed, as this package is managed manually by running terragrunt (or terraform) after changing the version number.                                                                                  |
| `mongo`                             | Pin Minor          | Pinned to a specific minor version (`8.0`) in accordance with other application compatibility constraints (unific-application-controller). Only `patch` updates are allowed, as updates of type `minor` introduce new features which might cause issues (and are not needed for proper functioning).                                                                              |
| `sidero/talos`                      | Manual             | No updates are allowed, as this package is managed manually by running terragrunt (or terraform) after changing the version number.                                                                                                                                                                                                                                               |

#### Excluded packages from auto-merging

Some packages are excluded from automerging due to their criticality or because they are managed by terragrunt, which requires manual handling. These packages are labeled with `updateStrategy:manual` in renovate configuration and excluded from automerging in mergify configuration. The exceptional packages are (as listed in the table above):

- `cilium`
- `isejalabs/terraform-proxmox-talos`
- `kubernetes/kubernetes`,
- `sidero/talos`

#### Excluded file paths from auto-merging

Some file paths are excluded from automerging due to the need for manual handling and review of changes, e.g. for testing or implementation purposes. These file paths are labeled with `updateStrategy:manual` in renovate configuration and excluded from automerging in mergify configuration. The exceptional file paths are:

- `.github/**`
- `terragrunt/**`
- `tofu/**`

## Pending

Some asprects still need to be investigated and tested further to ensure that the automerging of updates is working as expected and that the configuration is correctly set up to handle different types of updates and environments. These include:

- [ ] `automergeType=branch` not working (PRs get created nevertheless)
- [ ] investigate necessity for disabling updates for `mongo` and maybe `unifi-controller` (enabled currently)
- [X] pin `cilium`, `gateway-api` and `kubernetes` to specific minor versions to reduce PR noise; PRs only should get created when necessary without the need to ignore them "until a certain solution is released" or "depending on further testing"; PRs should be only ignored for a while if they
  - need to be handled manually for testing and/or implementation (e.g. manual handling of terraform/terragrunt), or
  - are waiting for promotion to production, e.g. due to the need for testing in a specific environment, or
  - are expected to cause issues, e.g. due to new features being introduced in a major (or minor) update; otherwise, PRs should be created and automerged as soon as they are available, even if they are for minor updates, to ensure that the latest versions are being tested and used.
