# Common configurations for units

This directory holds the configuration each unit type shares across the environments: one `<unit>.hcl` per unit type, with the module source (and usually its pinned version) and the inputs that are the same everywhere. Each environment's `<env>/<unit>/terragrunt.hcl` includes the matching file and adds only what differs for that environment. See [`terragrunt/README.md`](../README.md#how-a-units-configuration-is-assembled) for how the pieces fit and [`terragrunt/README.md`'s units table](../README.md#units) for what each unit provisions.

| File | Used by |
| --- | --- |
| `checkmk-longhorn-monitoring.hcl` | `checkmk-longhorn-monitoring` (`prod` only); also lists the monitored environments |
| `checkmk-password.hcl` | `checkmk-password` |
| `checkmk-rustfs-monitoring.hcl` | `checkmk-rustfs-monitoring` (`prod` only); also lists the monitored identities (`identity_envs`) |
| `keycloak-automation.hcl` | `keycloak-automation`; the service-account client of `keycloak-realm` |
| `keycloak-realm.hcl` | `keycloak-realm`; holds the directory facts and realm definitions |
| `rustfs-bucket-reader.hcl` | `rustfs-bucket-reader` |
| `rustfs-keycloak-db.hcl` | `rustfs-keycloak-db` |
| `rustfs-kopiur-backup.hcl` | `rustfs-kopiur-backup` |
| `talos-proxmox.hcl` | `talos-proxmox` (`poc` only) |
| `tf-state-read-role.hcl` | `tf-state-read-role` |
| `vehagn-k8s.hcl`, `vehagn-k8s/` | `vehagn-k8s`; the folder holds shared Talos machine-config patches |
| `vms.hcl` | `vms` (`poc` only) |

Terragrunt allows only one level of includes, so a file here can't include `root.hcl` itself: files that need the merged secrets repeat `root.hcl`'s decryption block. Refer to [the Terragrunt documentation](https://terragrunt.gruntwork.io/docs/features/keep-your-terragrunt-architecture-dry/) for more details.
