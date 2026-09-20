# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-09-20T12:46:23.949Z
> Files: 504 tracked | Anatomy hits: 0 | Misses: 0

> Project structure index. Auto-maintained by OpenWolf hooks and daemon.
> Run `openwolf scan` to generate, or wait for the first Claude Code session.
> Status: Pending initial scan

## ./

- `.gitattributes` — Git attributes (~19 tok)
- `.gitignore` — Git ignore rules (~124 tok)
- `.gitmodules` (~23 tok)
- `.justfile` (~225 tok)
- `.minijinja.toml` (~26 tok)
- `.mise.toml` (~220 tok)
- `.pre-commit-config.yaml` (~140 tok)
- `.sops.yaml` (~193 tok)
- `AGENTS.md` — Agent Instructions (~4427 tok)
- `CLAUDE.md` — OpenWolf (~4526 tok)
- `LICENSE` — Project license (~3029 tok)
- `README.md` — Project documentation (~2162 tok)

## .ci/prettier/

- `.prettierignore` (~10 tok)
- `.prettierrc.yaml` (~26 tok)

## .github/

- `labeler.yml` — vim:sw=2:ts=2:expandtab:ai (~516 tok)
- `mergify.yml` (~280 tok)
- `renovate.json5` (~609 tok)

## .github/renovate/

- `automerge-disable.json5` — ", "terragrunt/**", "tofu/**"], (~188 tok)
- `automerge-enable.json5` (~100 tok)
- `labels.json5` (~384 tok)
- `major-test-plan.json5` (~191 tok)
- `organize-semantic-scope.json5` (~307 tok)
- `pin-versions.json5` — /envs/head/**', (~728 tok)
- `renames.json5` (~556 tok)
- `schedule.json5` (~120 tok)
- `version-scheme.json5` (~266 tok)

## .github/workflows/

- `actionlint.yml` — CI: "Actionlint" (~112 tok)
- `bootstrap-apps-test.yml` — CI: "Bootstrap apps test" (~130 tok)
- `check-sorting.yml` — CI: "Sorting check" (~122 tok)
- `flate-test.yml` — CI: "Flate test" (~122 tok)
- `helmfile-template.yml` — CI: "Helmfile template" (~125 tok)
- `kustomize-build.yml` — CI: "Kustomize build" (~124 tok)
- `labeler.yml` — CI: "Pull Request Labeler" (~72 tok)
- `pre-commit.yml` — CI: "Pre-commit" (~182 tok)
- `renovate-config-validate.yml` — CI: "Renovate config validate" (~197 tok)
- `terragrunt-validate.yml` — CI: "Terragrunt validate" (~274 tok)

## _attic/docker/

- `docker-compose.yaml` — Docker Compose services (~745 tok)

## _attic/docker/apps/borgmatic/

- `docker-compose.yaml` — Docker Compose services (~185 tok)

## _attic/docker/apps/mongodb/config/

- `init-mongo.js` (~72 tok)

## _attic/docker/apps/openssh-server/

- `docker-compose.yaml` — Docker Compose services (~414 tok)

## _attic/k8s/apps/diag/openssh/base/

- `deployment.yaml` — K8s Deployment: ssh (~574 tok)
- `kustomization.yaml` — K8s Kustomization: ssh-install-packages-script (~79 tok)
- `ns.yaml` — K8s Namespace: _ (~69 tok)
- `pvc.yaml` — K8s PersistentVolumeClaim: test-data (~61 tok)
- `svc.yaml` — K8s Service: ssh (~73 tok)

## _attic/k8s/apps/diag/openssh/base/assets/

- `authorized_keys` (~77 tok)

## _attic/k8s/apps/diag/openssh/base/assets/custom-cont-init.d/

- `install-packages.sh` (~39 tok)

## _attic/k8s/apps/diag/openssh/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: ssh (~30 tok)

## _attic/k8s/apps/diag/openssh/envs/poc/

- `deployment.yaml` — K8s Deployment: ssh (~78 tok)
- `egress-gw-policy.yaml` — K8s CiliumEgressGatewayPolicy: egress-ssh (~317 tok)
- `kustomization.yaml` — K8s Kustomization (~64 tok)
- `svc.yaml` — K8s Service: ssh (~30 tok)

## _attic/k8s/apps/diag/shell/base/

- `deployment.yaml` — K8s Deployment: shell (~272 tok)
- `kustomization.yaml` — K8s Kustomization (~36 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## _attic/k8s/apps/diag/shell/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## _attic/k8s/apps/ras/openssh/base/

- `deployment.yaml` — K8s Deployment: ssh (~530 tok)
- `kustomization.yaml` — K8s Kustomization: ssh-install-packages-script (~75 tok)
- `ns.yaml` — K8s Namespace: _ (~69 tok)
- `svc.yaml` — K8s Service: ssh (~73 tok)

## _attic/k8s/apps/ras/openssh/base/assets/custom-cont-init.d/

- `install-packages.sh` (~20 tok)

## _attic/k8s/apps/ras/openssh/envs/poc/

- `egress-gw-policy.yaml` — K8s CiliumEgressGatewayPolicy: egress-ssh (~317 tok)
- `kustomization.yaml` — K8s Kustomization (~57 tok)
- `svc.yaml` — K8s Service: ssh (~30 tok)

## _attic/talos/

- `README.md` — Project documentation (~256 tok)

## _attic/talos/base/

- `kustomization.yaml` — K8s Kustomization (~28 tok)
- `talconfig.base.yaml` (~392 tok)

## _attic/talos/envs/dev/

- `hosts.txt` (~26 tok)
- `kustomization.yaml` — K8s Kustomization: talconfig (~90 tok)
- `talconfig.env.yaml` (~142 tok)
- `talconfig.patches.yaml` — IPv6, not working correctly (~198 tok)
- `talenv.yaml` (~106 tok)

## _attic/talos/envs/poc/

- `hosts.txt` (~26 tok)
- `kustomization.yaml` — K8s Kustomization: talconfig (~90 tok)
- `talconfig.env.yaml` (~142 tok)
- `talconfig.patches.yaml` — IPv6, not working correctly (~198 tok)
- `talenv.yaml` (~178 tok)
- `talsecret.sops.yaml` (~4099 tok)

## _attic/talos/envs/prod/

- `talenv.yaml` (~80 tok)
- `talsecret.sops.yaml` (~4094 tok)

## _attic/tofu/modules/terraform-state-read-role-tf-module/

- `.terraform.lock.hcl` — This file is maintained automatically by "tofu init". (~582 tok)
- `backend.tf` (~19 tok)
- `main.tf` — Our primary provider is in the Terraform account (~364 tok)
- `outputs.tf` (~123 tok)
- `providers.tf` (~281 tok)
- `variables.tf` — REQUIRED PARAMETERS (~180 tok)

## _attic/tofu/modules/vms/

- `providers.tf` (~105 tok)
- `variables.tf` (~275 tok)
- `vms.tf` (~537 tok)

## docs/

- `app-storage.md` — App storage (~1066 tok)
- `kopiur-backup-restore.md` — Kopiur Backup & Restore (~6681 tok)
- `README.md` — Project documentation (~828 tok)
- `update handling.md` — Update Handling and Automerging of PRs (~3129 tok)

## docs/architecture/

- `environments.md` — Environments (~3712 tok)
- `kustomize.md` — Kustomize overlay approach (~3271 tok)
- `network.md` — Networking (~3970 tok)
- `secrets.md` — Secrets management (~3686 tok)
- `storage.md` — Storage: Longhorn vs. proxmox-csi (~3009 tok)
- `workloads.md` — Cluster workload (~2348 tok)

## docs/logs/

- `INSTALL.log.prod.md` — Context (~10274 tok)
- `INSTALL.log.qa.md` — 2025-09-01 (~9724 tok)

## k8s/

- `README.md` — Project documentation (~821 tok)

## k8s/apps/diag/whoami/base/

- `deployment.yaml` — K8s Deployment: whoami (~295 tok)
- `http-route.yaml` — K8s HTTPRoute: whoami-ingress (~147 tok)
- `kustomization.yaml` — K8s Kustomization (~51 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)
- `svc-gw.yaml` — K8s Service: whoami-gw (~50 tok)
- `svc.yaml` — K8s Service: whoami (~74 tok)

## k8s/apps/diag/whoami/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/dev/

- `deployment.yaml` — K8s Deployment: whoami (~24 tok)
- `kustomization.yaml` — K8s Kustomization (~57 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/head/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/qa/

- `deployment.yaml` — K8s Deployment: whoami (~24 tok)
- `kustomization.yaml` — K8s Kustomization (~57 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~51 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/envs/src/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: whoami (~31 tok)

## k8s/apps/diag/whoami/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~118 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/dns/adguard/

- `README.md` — Project documentation (~87 tok)

## k8s/apps/dns/adguard/base/

- `deployment.yaml` — K8s Deployment: adguard (~818 tok)
- `http-route.yaml` — K8s HTTPRoute: adguard (~136 tok)
- `kustomization.yaml` — K8s Kustomization: adguard-config (~83 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)
- `secret-users.yaml` — K8s SealedSecret: users (~296 tok)
- `svc-ui.yaml` — K8s Service: adguard-ui (~50 tok)
- `svc.yaml` — K8s Service: adguard (~106 tok)

## k8s/apps/dns/adguard/base/config/

- `AdGuardHome.yaml` (~1234 tok)

## k8s/apps/dns/adguard/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/head/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/qa/

- `kustomization.yaml` — K8s Kustomization: adguard-config-local (~100 tok)
- `merge-deployment.yaml` — K8s Deployment: adguard (~54 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/qa/config/

- `AdGuardHome.yaml` (~1226 tok)

## k8s/apps/dns/adguard/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~51 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/envs/src/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: adguard (~31 tok)

## k8s/apps/dns/adguard/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~133 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/dns/unbound/base/

- `deployment.yaml` — K8s Deployment: unbound (~838 tok)
- `kustomization.yaml` — K8s Kustomization: unbound-env (~178 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)
- `svc.yaml` — K8s Service: unbound (~106 tok)

## k8s/apps/dns/unbound/base/config/

- `unbound.conf` (~97 tok)

## k8s/apps/dns/unbound/base/config/conf.d/

- `access-control.conf` (~91 tok)
- `logging-default.conf` (~85 tok)
- `logging-verbose.conf` (~107 tok)
- `rootless.conf` (~8 tok)

## k8s/apps/dns/unbound/base/config/zones.d/

- `unbound-iseja.conf` (~569 tok)

## k8s/apps/dns/unbound/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/envs/head/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/envs/prod/

- `deployment.yaml` — K8s Deployment: unbound (~24 tok)
- `kustomization.yaml` — K8s Kustomization (~57 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~49 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~51 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/envs/src/

- `kustomization.yaml` — K8s Kustomization (~50 tok)
- `svc.yaml` — K8s Service: unbound (~34 tok)

## k8s/apps/dns/unbound/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~120 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/finances/actualbudget/base/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~303 tok)
- `helmrepository.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json (~149 tok)
- `http-route.yaml` — K8s HTTPRoute: actualbudget (~137 tok)
- `kustomization.yaml` — K8s Kustomization (~91 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## k8s/apps/finances/actualbudget/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/finances/actualbudget/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/finances/actualbudget/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/finances/actualbudget/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/finances/actualbudget/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/finances/actualbudget/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/finances/actualbudget/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/finances/actualbudget/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/finances/actualbudget/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~154 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/monitoring/checkmk-agent/

- `README.md` — Project documentation (~3107 tok)

## k8s/apps/monitoring/checkmk-agent/base/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~360 tok)
- `helmrepository.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json (~150 tok)
- `http-route.yaml` — K8s HTTPRoute: cmk-ingress (~150 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)
- `ns.yaml` — K8s Namespace: _ (~81 tok)

## k8s/apps/monitoring/checkmk-agent/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/checkmk-agent/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/checkmk-agent/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/monitoring/checkmk-agent/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/apps/monitoring/checkmk-agent/envs/poc/patches/

- `log-level.yaml` — K8s HelmRelease: &name (~64 tok)

## k8s/apps/monitoring/checkmk-agent/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/monitoring/checkmk-agent/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/checkmk-agent/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/monitoring/checkmk-agent/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/checkmk-agent/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~127 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/monitoring/metrics-server/base/

- `helmrelease.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json (~83 tok)
- `kustomization.yaml` — K8s Kustomization (~42 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/ocirepository_v1.json (~147 tok)

## k8s/apps/monitoring/metrics-server/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/metrics-server/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/metrics-server/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/monitoring/metrics-server/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/metrics-server/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/monitoring/metrics-server/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/metrics-server/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/monitoring/metrics-server/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/monitoring/metrics-server/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~116 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/network/unifi-controller/

- `README.md` — Project documentation (~67 tok)

## k8s/apps/network/unifi-controller/base/

- `deployment-frontend.yaml` — K8s Deployment: unifi-controller (~838 tok)
- `kustomization.yaml` — K8s Kustomization (~62 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~172 tok)

## k8s/apps/network/unifi-controller/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/head/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~53 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/envs/src/

- `kustomization.yaml` — K8s Kustomization (~52 tok)
- `svc-frontend.yaml` — K8s Service: unifi-controller (~34 tok)

## k8s/apps/network/unifi-controller/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~178 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/apps/network/unifi-mongodb/base/

- `db-secret.sealed.yaml` — K8s SealedSecret: db-secret-sealed (~924 tok)
- `db-secret.unencrypted.yaml.example` (~49 tok)
- `deployment.yaml` — K8s Deployment: mongodb (~728 tok)
- `kustomization.yaml` — K8s Kustomization: mongodb-init (~99 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)
- `svc.yaml` — K8s Service: mongodb (~48 tok)

## k8s/apps/network/unifi-mongodb/base/assets/

- `init-mongo.sh` (~163 tok)

## k8s/apps/network/unifi-mongodb/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/network/unifi-mongodb/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/network/unifi-mongodb/envs/head/

- `kustomization.yaml` — K8s Kustomization (~51 tok)
- `version.yaml` — K8s Deployment: mongodb (~79 tok)

## k8s/apps/network/unifi-mongodb/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/network/unifi-mongodb/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/network/unifi-mongodb/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/network/unifi-mongodb/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/apps/network/unifi-mongodb/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/apps/network/unifi-mongodb/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~282 tok)
- `kustomization.yaml` — K8s Kustomization (~26 tok)

## k8s/bootstrap/

- `mod.just` (~534 tok)
- `README.md` — Project documentation (~4205 tok)

## k8s/bootstrap/cluster/flux/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~44 tok)

## k8s/bootstrap/cluster/flux/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~44 tok)

## k8s/bootstrap/cluster/flux/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/bootstrap/cluster/flux/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~44 tok)

## k8s/bootstrap/cluster/flux/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/bootstrap/cluster/flux/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/bootstrap/cluster/flux/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/bootstrap/cluster/flux/envs/src/

- `kustomization.yaml` — K8s Kustomization (~44 tok)

## k8s/bootstrap/cluster/flux/sets/

- `kustomization.yaml` — K8s Kustomization (~30 tok)

## k8s/bootstrap/cluster/flux/sets/apps/

- `kustomization.yaml` — K8s Kustomization (~38 tok)

## k8s/bootstrap/cluster/flux/sets/apps/minimal/

- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/bootstrap/cluster/flux/sets/apps/optional/

- `kustomization.yaml` — K8s Kustomization (~118 tok)

## k8s/bootstrap/cluster/flux/sets/infra/

- `kustomization.yaml` — K8s Kustomization (~38 tok)

## k8s/bootstrap/cluster/flux/sets/infra/minimal/

- `kustomization.yaml` — K8s Kustomization (~254 tok)

## k8s/bootstrap/cluster/flux/sets/infra/optional/

- `kustomization.yaml` — K8s Kustomization (~99 tok)

## k8s/bootstrap/cluster/flux/sets/minimal/

- `kustomization.yaml` — K8s Kustomization (~55 tok)

## k8s/bootstrap/helmfile/apps/

- `helmfile.yaml.gotmpl` — yaml-language-server: $schema=https://json.schemastore.org/helmfile (~1087 tok)

## k8s/bootstrap/helmfile/base/

- `environments.yaml` (~101 tok)
- `helmDefaults.yaml` (~20 tok)
- `kubeContext.yaml.gotmpl` (~22 tok)
- `release-templates.yaml` — yaml-language-server: $schema=https://json.schemastore.org/helmfile (~229 tok)

## k8s/bootstrap/helmfile/ci/

- `cilium-values.yaml` — Overrides for k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl's cilium release, applied only when (~450 tok)

## k8s/bootstrap/helmfile/crds/

- `helmfile.yaml` — yaml-language-server: $schema=https://json.schemastore.org/helmfile (~370 tok)

## k8s/bootstrap/helmfile/templates/

- `helmrelease-base-values.yaml.gotmpl` (~181 tok)
- `helmrelease-env-values.yaml.gotmpl` (~220 tok)
- `ocirelease.yaml.gotmpl` — 0. Some constants (~215 tok)

## k8s/bootstrap/kustomize/personal/

- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~51 tok)

## k8s/bootstrap/kustomize/personal/external-secrets/

- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~91 tok)
- `s3cr3t.yaml` — K8s Secret: onepassword-connect-credentials-secret (~95 tok)

## k8s/components/

- `README.md` — Project documentation (~624 tok)

## k8s/components/apps/kopiur/

- `README.md` — Project documentation (~256 tok)

## k8s/components/apps/kopiur/secret/

- `externalsecret.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json (~190 tok)
- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~50 tok)

## k8s/components/apps/storage/

- `README.md` — Project documentation (~993 tok)

## k8s/components/apps/storage/pvc-no-backup/

- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~70 tok)
- `pvc.yaml` — K8s PersistentVolumeClaim: ${APP} (~101 tok)
- `restore.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kopiur.home-operations.com/restore_v1alpha1.json (~100 tok)
- `snapshotpolicy.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kopiur.home-operations.com/snapshotpolicy_v1alpha1.json (~408 tok)

## k8s/components/apps/storage/pvc/

- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~61 tok)
- `snapshotschedule.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kopiur.home-operations.com/snapshotschedule_v1alpha1.json (~91 tok)

## k8s/components/envs/base/

- `cluster-base-param.yaml` — K8s ConfigMap: cluster-base-param (~46 tok)
- `kustomization.yaml` — K8s Component (~76 tok)

## k8s/components/envs/dbg/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~68 tok)
- `kustomization.yaml` — K8s Component (~80 tok)

## k8s/components/envs/dev/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~68 tok)
- `kustomization.yaml` — K8s Component (~66 tok)

## k8s/components/envs/head/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~68 tok)
- `kustomization.yaml` — K8s Component (~80 tok)

## k8s/components/envs/poc/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~68 tok)
- `kustomization.yaml` — K8s Component (~80 tok)

## k8s/components/envs/prod/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~68 tok)
- `kustomization.yaml` — K8s Component (~82 tok)

## k8s/components/envs/qa/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~67 tok)
- `kustomization.yaml` — K8s Component (~66 tok)

## k8s/components/envs/rebuild/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~70 tok)
- `kustomization.yaml` — K8s Component (~66 tok)

## k8s/components/envs/src/

- `cluster-param.yaml` — K8s ConfigMap: cluster-param (~68 tok)
- `kustomization.yaml` — K8s Component (~80 tok)

## k8s/components/transformers/add-labels/

- `kustomization.yaml` — K8s Component (~32 tok)

## k8s/components/transformers/add-labels/transf/

- `label-ConfigMaps.yaml` — K8s LabelTransformer: label-ConfigMaps (~79 tok)

## k8s/components/transformers/kopiur-secret-env/

- `kustomization.yaml` — K8s Component (~48 tok)
- `README.md` — Project documentation (~727 tok)

## k8s/components/transformers/kopiur-secret-env/repl/

- `clusterrepository-bucket.yaml` (~80 tok)
- `externalsecret-kopiur-key.yaml` — replace the last segment (after "#") of kopiur-repository's ExternalSecret (~165 tok)

## k8s/components/transformers/prefix-domain/

- `kustomization.yaml` — K8s Component (~59 tok)

## k8s/components/transformers/prefix-domain/repl/

- `httproute-prefix-domain.yaml` (~120 tok)
- `ingress-prefix-domain.yaml` (~70 tok)
- `tlsroute-prefix-domain.yaml` (~70 tok)

## k8s/components/transformers/replace-domain/

- `kustomization.yaml` — K8s Component (~85 tok)

## k8s/components/transformers/replace-domain/repl/

- `cert-replace-hostname.yaml` (~135 tok)
- `gateway-replace-hostname.yaml` (~227 tok)
- `httproute-replace-domain.yaml` (~226 tok)
- `ingress-replace-domain.yaml` (~134 tok)
- `tlsroute-replace-domain.yaml` (~134 tok)

## k8s/components/transformers/replace-path/

- `kustomization.yaml` — K8s Component (~34 tok)

## k8s/components/transformers/replace-path/repl/

- `flux-kustomize-path.yaml` — replace the last segment of the path of all Kustomizations with "envs/example" (~246 tok)

## k8s/components/transformers/set-flux-defaults/

- `kustomization.yaml` — K8s Component (~54 tok)

## k8s/components/transformers/set-flux-defaults/repl/

- `flux-helmrelease-reconcilation-interval.yaml` — replace .spec.interval of all Flux Kustomizations with the value of FLUX_RECONCILIATION_INTERVAL from the cluster-param ConfigMap (~107 tok)
- `flux-ks-reconcilation-interval.yaml` — replace .spec.interval of all Flux Kustomizations with the value of FLUX_RECONCILIATION_INTERVAL from the cluster-param ConfigMap (~109 tok)

## k8s/components/transformers/suspend-kopiur-schedule/

- `kustomization.yaml` — K8s Component (~41 tok)
- `patch-suspend.yaml` (~17 tok)
- `README.md` — Project documentation (~325 tok)

## k8s/infra/cert-manager/_ns/base/

- `kustomization.yaml` — K8s Kustomization (~33 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## k8s/infra/cert-manager/cert-manager/

- `README.md` — Project documentation (~109 tok)

## k8s/infra/cert-manager/cert-manager/base/

- `cloudflare-api-token.yaml` — K8s SealedSecret: cloudflare-api-token (~294 tok)
- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~137 tok)
- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.bjw-s.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json (~271 tok)
- `kustomization.yaml` — K8s Kustomization (~57 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://k8s-schemas.bjw-s.dev/source.toolkit.fluxcd.io/ocirepository_v1.json (~140 tok)

## k8s/infra/cert-manager/cert-manager/envs/dbg/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~42 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/infra/cert-manager/cert-manager/envs/dev/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~59 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/infra/cert-manager/cert-manager/envs/head/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~42 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/infra/cert-manager/cert-manager/envs/poc/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~42 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/infra/cert-manager/cert-manager/envs/prod/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~59 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/infra/cert-manager/cert-manager/envs/qa/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~59 tok)
- `kustomization.yaml` — K8s Kustomization (~52 tok)

## k8s/infra/cert-manager/cert-manager/envs/rebuild/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~43 tok)
- `kustomization.yaml` — K8s Kustomization (~54 tok)

## k8s/infra/cert-manager/cert-manager/envs/src/

- `cluster-issuer.yaml` — K8s ClusterIssuer: cloudflare-cluster-issuer (~42 tok)
- `kustomization.yaml` — K8s Kustomization (~53 tok)

## k8s/infra/cert-manager/cert-manager/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~115 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/infra/common/ns/base/

- `kustomization.yaml` — K8s Kustomization (~164 tok)

## k8s/infra/common/ns/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/common/ns/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/common/ns/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/common/ns/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/common/ns/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/common/ns/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/common/ns/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/common/ns/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/common/ns/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~110 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/infra/csi-proxmox/_ns/base/

- `kustomization.yaml` — K8s Kustomization (~32 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## k8s/infra/csi-proxmox/proxmox-csi/

- `README.md` — Project documentation (~498 tok)

## k8s/infra/csi-proxmox/proxmox-csi/base/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~153 tok)
- `kustomization.yaml` — K8s Kustomization (~42 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json (~118 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/csi-proxmox/proxmox-csi/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/csi-proxmox/proxmox-csi/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~124 tok)
- `kustomization.yaml` — K8s Kustomization (~26 tok)

## k8s/infra/external-secrets/

- `README.md` — Project documentation (~355 tok)

## k8s/infra/external-secrets/_ns/base/

- `kustomization.yaml` — K8s Kustomization (~34 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## k8s/infra/external-secrets/external-secrets/base/

- `grafanadashboard.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadashboard_v1beta1.json (~143 tok)
- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~131 tok)
- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~77 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json (~147 tok)
- `pdb.yaml` — K8s PodDisruptionBudget: external-secrets-webhook (~73 tok)

## k8s/infra/external-secrets/external-secrets/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/external-secrets/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/external-secrets/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/external-secrets/external-secrets/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/external-secrets/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/external-secrets/external-secrets/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/external-secrets/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/external-secrets/external-secrets/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/external-secrets/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~128 tok)
- `kustomization.yaml` — K8s Kustomization (~26 tok)

## k8s/infra/external-secrets/onepassword-connect/base/

- `clustersecretstore.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/clustersecretstore_v1.json (~159 tok)
- `externalsecret.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json (~282 tok)
- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~186 tok)
- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~80 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json (~141 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/external-secrets/onepassword-connect/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/external-secrets/onepassword-connect/flux/

- `ks.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~290 tok)
- `kustomization.yaml` — K8s Kustomization (~26 tok)

## k8s/infra/flux-system/_ns/base/

- `kustomization.yaml` — K8s Kustomization (~32 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## k8s/infra/flux-system/flux-instance/base/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~240 tok)
- `kustomization.yaml` — yaml-language-server: $schema=https://json.schemastore.org/kustomization (~64 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json (~147 tok)

## k8s/infra/flux-system/flux-instance/envs/dbg/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~127 tok)
- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/infra/flux-system/flux-instance/envs/dev/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~127 tok)
- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/infra/flux-system/flux-instance/envs/head/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~122 tok)
- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/infra/flux-system/flux-instance/envs/poc/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~121 tok)
- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/infra/flux-system/flux-instance/envs/prod/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~87 tok)
- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/infra/flux-system/flux-instance/envs/qa/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~121 tok)
- `kustomization.yaml` — K8s Kustomization (~58 tok)

## k8s/infra/flux-system/flux-instance/envs/rebuild/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~122 tok)
- `kustomization.yaml` — K8s Kustomization (~60 tok)

## k8s/infra/flux-system/flux-instance/envs/src/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~127 tok)
- `kustomization.yaml` — K8s Kustomization (~59 tok)

## k8s/infra/flux-system/flux-instance/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~116 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/infra/flux-system/flux-operator/base/

- `helmrelease.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json (~134 tok)
- `http-route.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/gateway.networking.k8s.io/httproute_v1.json (~171 tok)
- `kustomization.yaml` — K8s Kustomization (~48 tok)
- `ocirepository.yaml` — yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json (~146 tok)

## k8s/infra/flux-system/flux-operator/envs/dbg/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/flux-system/flux-operator/envs/dev/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/flux-system/flux-operator/envs/head/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/flux-system/flux-operator/envs/poc/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/flux-system/flux-operator/envs/prod/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/flux-system/flux-operator/envs/qa/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/flux-system/flux-operator/envs/rebuild/

- `kustomization.yaml` — K8s Kustomization (~42 tok)

## k8s/infra/flux-system/flux-operator/envs/src/

- `kustomization.yaml` — K8s Kustomization (~41 tok)

## k8s/infra/flux-system/flux-operator/flux/

- `ks.yaml` — yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json (~125 tok)
- `kustomization.yaml` — K8s Kustomization (~25 tok)

## k8s/infra/gateway-api/_ns/base/

- `kustomization.yaml` — K8s Kustomization (~32 tok)
- `ns.yaml` — K8s Namespace: _ (~34 tok)

## k8s/infra/gateway-api/gateway/

- `README.md` — Project documentation (~317 tok)

## k8s/infra/gateway-api/gateway/base/

- `cert.yaml` — K8s Certificate: cert (~100 tok)
- `gw-external.yaml` — K8s Gateway: external (~134 tok)
- `gw-internal-http.yaml` — K8s Gateway: internal-http (~224 tok)
- `gw-internal.yaml` — K8s Gateway: internal (~262 tok)
- `http-route-redirect.yaml` — K8s HTTPRoute: http-redirect-to-https (~130 tok)
- `kustomization.yaml` — K8s Kustomization (~61 tok)

## k8s/infra/gateway-api/gateway/envs/dbg/

- `gw-external.yaml` — K8s Gateway: external (~47 tok)
- `gw-internal-http.yaml` — K8s Gateway: internal-http (~48 tok)
- `gw-internal.yaml` — K8s Gateway: internal (~47 tok)
- `kustomization.yaml` — K8s Kustomization (~69 tok)

## k8s/infra/gateway-api/gateway/envs/dev/

- `gw-external.yaml` — K8s Gateway: external (~47 tok)
- `gw-internal-http.yaml` — K8s Gateway: internal-http (~48 tok)
- `gw-internal.yaml` — K8s Gateway: internal (~47 tok)
- `kustomization.yaml` — K8s Kustomization (~69 tok)

## k8s/infra/gateway-api/gateway/envs/head/

- `gw-external.yaml` — K8s Gateway: external (~47 tok)
- `gw-internal-http.yaml` — K8s Gateway: internal-http (~48 tok)
- `gw-internal.yaml` — K8s Gateway: internal (~47 tok)
- `kustomization.yaml` — K8s Kustomization (~69 tok)

## k8s/infra/gateway-api/gateway/envs/poc/

- `gw-external.yaml` — K8s Gateway: external (~47 tok)
- `gw-internal-http.yaml` — K8s Gateway: internal-http (~48 tok)
- `gw-internal.yaml` — K8s Gateway: internal (~47 tok)
- `gw-tls-passthrough.yaml` — K8s Gateway: tls-passthrough (~116 tok)
- `kustomization.yaml` — K8s Kustomization (~77 tok)
