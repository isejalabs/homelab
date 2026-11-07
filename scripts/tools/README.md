# Stand-alone tools

Scripts a human runs by hand; nothing wraps them in `just` and no workflow calls them. Each script documents its purpose and usage in a header comment; this README is an index, not a duplicate of that. All of them source [`lib/common.sh`](../lib/common.sh) for logging.

## SOPS bulk operations

Run from the repo root. See [`docs/architecture/secrets.md`](../../docs/architecture/secrets.md) for how SOPS fits into the repo's secrets handling.

| Script | Purpose |
| --- | --- |
| [`sops-encrypt-all.sh`](sops-encrypt-all.sh) | re-encrypts every plaintext file matched by a `.sops.yaml` `path_regex` into its `*.sops.yaml` sibling |
| [`sops-decrypt-all.sh`](sops-decrypt-all.sh) | decrypts every `*.sops.yaml` into its plaintext sibling (`-f`/`--force` to overwrite local edits) |

## Terragrunt state cleanup

Run from the relevant terragrunt unit directory (not the repo root) — see [`terragrunt/README.md`](../../terragrunt/README.md) for the destroy/rebuild workflows these support.

| Script | Purpose |
| --- | --- |
| [`tg-state-rm.sh`](tg-state-rm.sh) | drops state for resources that block `terragrunt destroy` on an unreachable cluster |
| [`volume-remove-state.sh`](volume-remove-state.sh) | drops Proxmox-volume state so `terragrunt destroy` preserves the real disks for reuse |

## Checkmk checks

Run against one Checkmk site; see [`docs/identity/checkmk-sso.md`](../../docs/identity/checkmk-sso.md#regression-check-agent-registration). Needs `curl` and `gum`.

| Script | Purpose |
| --- | --- |
| [`checkmk-agent-registration-check.sh`](checkmk-agent-registration-check.sh) | non-destructive regression check that agent registration still works on a site: a wrong password is refused with 401, and the registration user is accepted for an unknown host name (404 `does not exist`), without registering anything; the secret comes from `CMK_REGISTRATION_PASSWORD` |

## RustFS monitoring identity

Needs 1Password and network access to the RustFS, so not for CI — see the "RustFS monitoring identity" section of [`terragrunt/README.md`](../../terragrunt/README.md) for what the identity is and how to read the output.

| Script | Purpose |
| --- | --- |
| [`rustfs-verify-monitoring.sh`](rustfs-verify-monitoring.sh) | verifies one environment's `<env>-checkmk-monitoring` identity reads quota of its own buckets and is denied everything else (non-mutating) |

## Keycloak availability drill

Disrupts the cluster, needs a kubecontext and network access to Keycloak, so not for CI — see [`docs/identity/keycloak-drain-drill.md`](../../docs/identity/keycloak-drain-drill.md) for the procedure, the probes and how to read the report.

| Script | Purpose |
| --- | --- |
| [`keycloak-drain-drill.sh`](keycloak-drain-drill.sh) | drains the node of the Keycloak database (or, with `--observe`, only measures while something else disturbs it) and reports the login outage windows, a pod-event timeline and the image pull times; checks the control plane first and refuses `prod` |
