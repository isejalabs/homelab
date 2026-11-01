# Project icons

The logos shown in front of each unit in the [workload catalog](../../architecture/workloads.md). Each is the project's own icon, taken from the project's repository (or, where noted, from the community icon collection [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons)) and kept as published, except for the resizing noted below. The logos are trademarks and copyright of their projects and are used only to identify them.

Format: SVG or PNG only (the docs site does not serve `.ico`). In the catalog an icon is a raw `<img width="20" height="20" alt="">`; the site hook in [`.ci/mkdocs/hooks.py`](../../../.ci/mkdocs/hooks.py) fixes its relative path for the site.

To add one: copy the project's icon (not its wordmark) here as `<project>.svg` or `.png` (at most about 128 px for a PNG), add a row below, and reference it from the catalog row. A unit with no logo of its own keeps an emoji. Check the icon on a light and a dark background before committing.

| File | Project | Source | Used by |
| --- | --- | --- | --- |
| `1password.svg` | 1Password | [dashboard-icons `1password.svg`](https://github.com/homarr-labs/dashboard-icons/blob/main/svg/1password.svg) | `onepassword-connect` |
| `actual-budget.png` | Actual Budget | [actualbudget/docs `static/img/favicon.png`](https://github.com/actualbudget/docs/blob/master/static/img/favicon.png) | `actualbudget` |
| `adguard-home.svg` | AdGuard Home | [AdGuardHome `client_v2/public/assets/favicon.svg`](https://github.com/AdguardTeam/AdGuardHome/blob/master/client_v2/public/assets/favicon.svg) | `adguard` |
| `cert-manager.svg` | cert-manager | [cert-manager `logo/logo.svg`](https://github.com/cert-manager/cert-manager/blob/master/logo/logo.svg) | `cert-manager` |
| `checkmk.svg` | Checkmk | [dashboard-icons `checkmk.svg`](https://github.com/homarr-labs/dashboard-icons/blob/main/svg/checkmk.svg) | `checkmk-agent` |
| `cilium.svg` | Cilium | [dashboard-icons `cilium.svg`](https://github.com/homarr-labs/dashboard-icons/blob/main/svg/cilium.svg) (Cilium's own repository only has a wordmark) | `cilium` |
| `cloudnative-pg.svg` | CloudNativePG | [cncf/artwork `cloudnativepg-icon-color.svg`](https://github.com/cncf/artwork/blob/main/projects/cloudnativepg/icon/color/cloudnativepg-icon-color.svg) | `cloudnative-pg` |
| `external-dns.png` | external-dns | [external-dns `docs/img/external-dns.png`](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/img/external-dns.png), scaled from 1586 px to 128 px | `external-dns` |
| `external-secrets.svg` | External Secrets Operator | [external-secrets `docs/pictures/eso-round-logo.svg`](https://github.com/external-secrets/external-secrets/blob/main/docs/pictures/eso-round-logo.svg) | `external-secrets` |
| `flux.svg` | Flux | [cncf/artwork `flux-icon-color.svg`](https://github.com/cncf/artwork/blob/main/projects/flux/icon/color/flux-icon-color.svg) | `flux-instance` |
| `flux-operator.svg` | Flux Operator | [flux-operator `docs/logo/flux-operator-icon.svg`](https://github.com/controlplaneio-fluxcd/flux-operator/blob/main/docs/logo/flux-operator-icon.svg) | `flux-operator` |
| `gateway-api.svg` | Gateway API | [gateway-api `site/static/images/logo/logo.svg`](https://github.com/kubernetes-sigs/gateway-api/blob/main/site/static/images/logo/logo.svg) | `gateway`, `gateway-api-crds` |
| `keycloak.svg` | Keycloak | [keycloak-web `resources/images/icon.svg`](https://github.com/keycloak/keycloak-web/blob/main/resources/images/icon.svg) | `keycloak`, `keycloak-operator` |
| `kopiur.svg` | kopiur | [kopiur `crates/ui/web/public/favicon.svg`](https://github.com/home-operations/kopiur/blob/main/crates/ui/web/public/favicon.svg) | `kopiur`, `kopiur-repository` |
| `longhorn.svg` | Longhorn | [cncf/artwork `longhorn-icon-color.svg`](https://github.com/cncf/artwork/blob/main/projects/longhorn/icon/color/longhorn-icon-color.svg) | `longhorn`, `longhorn-core` |
| `mongodb.svg` | MongoDB | [mongo `docs/leaf.svg`](https://github.com/mongodb/mongo/blob/master/docs/leaf.svg) | `unifi-mongodb` |
| `powerdns.png` | PowerDNS | [pdns `website/docs.powerdns.com/website/img/favicon.png`](https://github.com/PowerDNS/pdns/blob/master/website/docs.powerdns.com/website/img/favicon.png) | `powerdns` |
| `proxmox-csi.png` | Proxmox CSI plugin | [proxmox-csi-plugin `charts/proxmox-csi-plugin/icon.png`](https://github.com/sergelogvinov/proxmox-csi-plugin/blob/main/charts/proxmox-csi-plugin/icon.png) (the chart's icon; it has a grey background) | `proxmox-csi` |
| `sealed-secrets.png` | Sealed Secrets | [sealed-secrets `site/themes/template/static/img/sealedsecrets-logo.svg`](https://github.com/bitnami-labs/sealed-secrets/blob/main/site/themes/template/static/img/sealedsecrets-logo.svg): the wordmark wraps a PNG, cropped to its left 56 × 56 px (the mark without the text) | `sealed-secrets` |
| `unbound.png` | Unbound | [unbound `winrc/unbound256.png`](https://github.com/NLnetLabs/unbound/blob/master/winrc/unbound256.png), scaled from 256 px to 128 px | `unbound` |
| `unifi.svg` | UniFi | [dashboard-icons `unifi.svg`](https://github.com/homarr-labs/dashboard-icons/blob/main/svg/unifi.svg) | `unifi-controller` |
| `zigbee2mqtt.svg` | Zigbee2MQTT | [zigbee2mqtt `images/logo_vector.svg`](https://github.com/Koenkk/zigbee2mqtt/blob/master/images/logo_vector.svg) | `zigbee2mqtt` |

No logo of their own, so these units keep an emoji: `metrics-server`, `whoami`, `kubelet-serving-cert-approver`, `ns` (this repository's own aggregator) and `snapshot-controller`.
