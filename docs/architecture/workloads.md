# Cluster workload

A catalog of everything actually running in the cluster — every app under
[`k8s/apps/`](../../k8s/apps/) and every infra component under [`k8s/infra/`](../../k8s/infra/) — in the
spirit of [billimek/k8s-gitops](https://github.com/billimek/k8s-gitops/)'s single-table workload overview.
This doc only says **what** runs and **where**; for **how** the pieces work, see the other architecture docs
it links out to rather than duplicates: [`kustomize.md`](kustomize.md) for the `base`/`envs/<env>`/`flux`
overlay shape every entry below follows, and [`environments.md`](environments.md) for the minimal-vs-full
app split referenced throughout.

## Apps (`k8s/apps/`)

Every environment gets the two **minimal** apps; only `head`, `prod`, `qa`, `rebuild` also get the five
**optional** ones (see [`environments.md`](environments.md#1-which-apps-run-there--the-flux-minimalfull-split)).

| Category | App | What it is | Manifest | Flux set |
| --- | --- | --- | --- | --- |
| `diag` | [`whoami`](../../k8s/apps/diag/whoami/) | Traefik's [`whoami`](https://github.com/traefik/whoami) HTTP echo/debug server (`ghcr.io/traefik/whoami`) | raw Deployment/Service | minimal |
| `monitoring` | [`metrics-server`](../../k8s/apps/monitoring/metrics-server/) | Kubernetes [`metrics-server`](https://github.com/kubernetes-sigs/metrics-server) (resource metrics for `kubectl top`/HPA) | HelmRelease (OCI chart) | minimal |
| `dns` | [`adguard`](../../k8s/apps/dns/adguard/) | [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) — LAN DNS filtering/ad-blocking (see [`network.md`](network.md#dns-adguard--unbound)) | raw Deployment/Service, not a Helm chart | optional |
| `dns` | [`unbound`](../../k8s/apps/dns/unbound/) | [Unbound](https://github.com/NLnetLabs/unbound) — recursive/validating DNS resolver, AdGuard's upstream for the internal domain (see [`network.md`](network.md#dns-adguard--unbound)) | raw Deployment/Service, not a Helm chart | optional |
| `finances` | [`actualbudget`](../../k8s/apps/finances/actualbudget/) | [Actual Budget](https://github.com/actualbudget/actual) — personal finance/budgeting app | HelmRelease (`community-charts`) | optional |
| `monitoring` | [`checkmk-agent`](../../k8s/apps/monitoring/checkmk-agent/) | [Checkmk](https://checkmk.com/) Kubernetes monitoring agent (cluster + node collectors) | HelmRelease (`checkmk.github.io/checkmk_kube_agent`) | optional |
| `network` | [`unifi-controller`](../../k8s/apps/network/unifi-controller/) | [UniFi Network Application](https://www.ui.com/) — management UI for the physical WiFi APs/switches (see [`network.md`](network.md#physical-network-opnsense-ucs-and-the-root-nameservers)), plus its own MongoDB backing store on proxmox-csi (see [`storage.md`](storage.md)) | raw Deployments/Services (app + `mongo`), not a Helm chart | optional |

## Infra (`k8s/infra/`)

Every environment gets the **full** infra set — both `minimal` and `optional` — regardless of which app set
it runs (see [`environments.md`](environments.md#1-which-apps-run-there--the-flux-minimalfull-split)). A few
of these are installed live by the bootstrap `helmfile` *before* Flux exists, in the dependency order shown,
then handed off to Flux for ongoing management — see [`k8s/bootstrap/README.md`](../../k8s/bootstrap/README.md)
for the full bootstrap walkthrough; this table only says which ones.

| Category | Component | What it is | Bootstrap helmfile? | Flux set |
| --- | --- | --- | --- | --- |
| `kube-system` | [`cilium`](../../k8s/infra/kube-system/cilium/) | [Cilium](https://cilium.io/) — CNI, kube-proxy replacement, Gateway API implementation, LB-IPAM, BGP (see [`network.md`](network.md#cilium-lb-ipam-and-bgp-route-advertisement)) | yes — first release, everything else `needs` it | minimal |
| `sealed-secrets` | [`sealed-secrets`](../../k8s/infra/sealed-secrets/sealed-secrets/) | [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) controller (see [`secrets.md`](secrets.md)) | yes — needs `cilium` | minimal |
| `external-secrets` | [`external-secrets`](../../k8s/infra/external-secrets/external-secrets/) | [External Secrets Operator](https://external-secrets.io/) (see [`secrets.md`](secrets.md)) | yes — needs `cilium` | minimal |
| `external-secrets` | [`onepassword-connect`](../../k8s/infra/external-secrets/onepassword-connect/) | [1Password Connect](https://developer.1password.com/docs/connect/) server backing the `ClusterSecretStore` (see [`secrets.md`](secrets.md)) | yes — needs `external-secrets` | minimal |
| `cert-manager` | [`cert-manager`](../../k8s/infra/cert-manager/cert-manager/) | [cert-manager](https://cert-manager.io/), Gateway API support enabled (see [`network.md`](network.md#gateway-api-cilium-as-the-implementation)) | yes — needs `sealed-secrets` | minimal |
| `flux-system` | [`flux-operator`](../../k8s/infra/flux-system/flux-operator/) | ControlPlane's [Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator) | yes — needs `cert-manager` | minimal |
| `flux-system` | [`flux-instance`](../../k8s/infra/flux-system/flux-instance/) | The `FluxInstance` CR — the actual Flux controllers, pointed at this repo/branch. Installing this is the bootstrap → Flux handoff point | yes — needs `flux-operator`; last bootstrap step | minimal |
| `csi-proxmox` | [`proxmox-csi`](../../k8s/infra/csi-proxmox/proxmox-csi/) | [sergelogvinov/proxmox-csi-plugin](https://github.com/sergelogvinov/proxmox-csi-plugin) (see [`storage.md`](storage.md)) | no — Flux-only | minimal |
| `gateway-api` | [`gateway-api-crds`](../../k8s/infra/gateway-api/gateway-api-crds/) | Upstream Gateway API CRDs (standard + experimental `TLSRoute`), raw manifests from a GitHub release | no — Flux-only | minimal |
| `gateway-api` | [`gateway`](../../k8s/infra/gateway-api/gateway/) | The actual `Gateway`/`HTTPRoute`/`Certificate` resources (see [`network.md`](network.md#gateway-api-cilium-as-the-implementation)) | no — Flux-only | minimal |
| `kube-system` | [`kubelet-serving-cert-approver`](../../k8s/infra/kube-system/kubelet-serving-cert-approver/) | [alex1989hu/kubelet-serving-cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver), raw manifest from a GitHub release | no — Flux-only | minimal |
| `kube-system` | [`snapshot-controller`](../../k8s/infra/kube-system/snapshot-controller/) | [`snapshot-controller`](https://github.com/kubernetes-csi/external-snapshotter) (VolumeSnapshot CRDs/controller) | CRDs only, pre-Flux; the release itself is Flux-only | minimal |
| `common` | [`ns`](../../k8s/infra/common/ns/) | Namespace-registration aggregator — creates the namespaces every other infra unit below deploys into (`_ns/` folders throughout `k8s/infra/` are inputs to this one unit, not standalone entries) | no — Flux-only | minimal |
| `longhorn-system` | [`longhorn-core`](../../k8s/infra/longhorn-system/longhorn-core/) | [Longhorn](https://longhorn.io/) distributed block storage engine (see [`storage.md`](storage.md)) | no — Flux-only | optional |
| `longhorn-system` | [`longhorn`](../../k8s/infra/longhorn-system/longhorn/) | Longhorn's `StorageClass`es, `VolumeSnapshotClass`, and backup/trim/snapshot jobs — companion to `longhorn-core` | no — Flux-only | optional |
| `kopiur-system` | [`kopiur`](../../k8s/infra/kopiur-system/kopiur/) | [kopiur](https://github.com/home-operations/kopiur) backup/restore operator, kopia-based (see [`storage.md`](storage.md) and [`docs/kopiur-backup-restore.md`](../kopiur-backup-restore.md)) | no — Flux-only | optional |
| `kopiur-system` | [`kopiur-repository`](../../k8s/infra/kopiur-system/kopiur-repository/) | `fiona`, kopiur's `ClusterRepository` pointing at this cluster's S3-compatible NAS, one bucket per environment | no — Flux-only | optional |

### CRDs-only, not actually deployed

[`o11y/grafana-operator`](../../k8s/infra/o11y/grafana-operator/) and
[`o11y/kube-prometheus-stack`](../../k8s/infra/o11y/kube-prometheus-stack/) each contain only an
`ocirepository.yaml` — no `HelmRelease`, no `flux/` folder, and neither is referenced by either Flux infra
set. They exist solely so the bootstrap `crds` helmfile can extract and pre-install their CRDs
(`--include-crds --no-hooks`, same mechanism `snapshot-controller`'s CRDs use above). **Neither release is
actually running anywhere in this repo today** — if an observability stack (Grafana + Prometheus) gets built
out, these are the CRD groundwork already laid for it, not evidence it already exists.

## Bootstrap install order

The `apps` helmfile installs the bootstrap-managed pieces above in this dependency chain, before Flux exists
to do it declaratively (see [`k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl`](../../k8s/bootstrap/helmfile/apps/helmfile.yaml.gotmpl)
for the authoritative `needs:` graph):

```
cilium
  ├─▶ sealed-secrets
  │     └─▶ cert-manager ─▶ flux-operator ─▶ flux-instance  (hands off to Flux)
  └─▶ external-secrets ─▶ onepassword-connect
```

Everything else in the tables above — `proxmox-csi`, `gateway-api-crds`, `gateway`,
`kubelet-serving-cert-approver`, `common/ns`, `snapshot-controller`'s release itself, `longhorn-core`,
`longhorn`, and every app in the first table — is purely Flux-managed from the start; the bootstrap helmfile
never touches them (`snapshot-controller`, `grafana-operator`, and `kube-prometheus-stack` are pre-seeded
CRDs-only, as noted above).
