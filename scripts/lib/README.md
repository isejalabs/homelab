# Shared shell code

Libraries the scripts under `ci/`, `ops/` and `tools/` source; they are never run directly. A script finds them through `SCRIPTS_DIR`, which it sets to the `scripts/` folder itself (`. "${SCRIPTS_DIR}/lib/common.sh"`) — the exact line is in the usage comment of [`common.sh`](common.sh). The header of each file says what it expects from its caller.

| Library | Shell | What it provides | Sourced by |
| --- | --- | --- | --- |
| [`common.sh`](common.sh) | POSIX `sh` | gum-backed logging, environment validation, kubecontext construction and unrecognized-flag handling | every script under `ops/` and `tools/`, and seven under `ci/` |
| [`proxmox.sh`](proxmox.sh) | bash | Proxmox API auth, VM discovery and task polling | the scripts under `ops/proxmox/`, after `common.sh` |
| [`longhorn.sh`](longhorn.sh) | bash | PVC to Longhorn volume lookup | the scripts under `ops/longhorn/`, after `common.sh` |
| [`flux-sets.sh`](flux-sets.sh) | POSIX `sh` | which units exist, which Flux set lists a unit and which environments run it; independent of `common.sh` on purpose, so the checks need only `sh`, `awk` and `sed` | `ci/check-workloads-catalog.sh`, `ci/check-unit-readmes.sh`, `ci/check-unit-readme-hostnames.sh`, `ci/test-readme-access.sh` |
| [`readme-access.sh`](readme-access.sh) | POSIX `sh` | the hostnames a unit README's `Access` section links and the environment a hostname belongs to; needs `flux-sets.sh` sourced first | `ci/check-unit-readme-hostnames.sh`, `ci/test-readme-access.sh` |
