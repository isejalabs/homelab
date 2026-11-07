# UniFi Network Application

The [UniFi Network Application](https://www.ui.com/) (the "UniFi controller", image from LinuxServer.io) is the management and adoption UI for the physical WiFi access points and switches. No cluster traffic flows through it.

## At a glance

| | |
| --- | --- |
| Namespace | `unifi` (created by `unifi-mongodb`, which owns it) |
| Runs in | `head`, `prod`, `qa`, `rebuild` (Flux set `optional`) |
| Installed via | Raw manifests (Deployment, `LoadBalancer` Service) and the `apps/storage/pvc` component (500M, backed up by kopiur) |
| Flux Kustomization | `unifi-controller`, depends on `cilium`, `gateway-api`, `proxmox-csi`, `sealed-secrets`, `unifi-mongodb` |

## Purpose

Configures and monitors the access points and switches of the physical network. The devices talk to it directly (inform, discovery, STUN), so it is exposed as a load balancer address, not through the Gateway. Where it sits in the network picture: [`network.md`](../../../../docs/architecture/network.md).

## Where it is used

- **Used by**: the UniFi devices on the LAN, and whoever administers them.
- **Depends on**: [`unifi-mongodb`](../unifi-mongodb/README.md) (service `mongodb`, credentials from the SealedSecret `db-secret-sealed`), `cilium` for the address, and its own PVC for the controller data.

## Access

A `LoadBalancer` Service with a fixed address per environment, also published by external-dns as `unifi-controller.<env>.iseja.net` (with the prefix, `qa-unifi-controller.qa.iseja.net`). There is no `HTTPRoute`; the UI is on port `8443` over HTTPS with the controller's own certificate.

| env | UI | Address |
| --- | --- | --- |
| `head` | [https://head-unifi-controller.head.iseja.net:8443](https://head-unifi-controller.head.iseja.net:8443) | `10.8.1.20` |
| `qa` | [https://qa-unifi-controller.qa.iseja.net:8443](https://qa-unifi-controller.qa.iseja.net:8443) | `10.8.2.20` |
| `rebuild` | [https://rebuild-unifi-controller.rebuild.iseja.net:8443](https://rebuild-unifi-controller.rebuild.iseja.net:8443) | `10.8.7.20` |
| `prod` | [https://unifi-controller.prod.iseja.net:8443](https://unifi-controller.prod.iseja.net:8443) | `10.8.8.20` |

Other ports on the same address: `8080` (device inform), `3478` (STUN), `10001` (discovery), `8843` and `8880` (guest portal).

## Updates

- **Image**: `lscr.io/linuxserver/unifi-network-application` with tag and digest in [`base/deployment-frontend.yaml`](base/deployment-frontend.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies. Mind that a major version can need a matching MongoDB version (the database is pinned to 8.0, see [`unifi-mongodb`](../unifi-mongodb/README.md#updates)).

## Operations

| Task | Doc |
| --- | --- |
| Back up and restore the controller data | [`kopiur-backup-restore.md`](../../../../docs/backup/kopiur-backup-restore.md) |
| PVC or volume problems | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |

## Cheat sheet

```sh
flux get ks unifi-mongodb unifi-controller --context admin@<env>-homelab
kubectl get pods,svc,pvc -n unifi --context admin@<env>-homelab

# logs of the controller
kubectl logs -n unifi -l app=unifi-controller -f --context admin@<env>-homelab
```

## Upstream

- Application: <https://www.ui.com/>
- Image: <https://github.com/linuxserver/docker-unifi-network-application>

## Known quirks

From the earlier version of this README, written when the volumes were static `proxmox-csi` PersistentVolumes (`pv-unifi`, `pv-mongodb`): a PVC that stays pending with `volume "foo" already bound to a different claim` is released by clearing the PV's claim reference. It does not apply to the current PVCs from `apps/storage/pvc`; for those see [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md).

```sh
kubectl patch pv pv-mongodb -p '{"spec":{"claimRef": null}}'
kubectl patch pv pv-unifi -p '{"spec":{"claimRef": null}}'
```
