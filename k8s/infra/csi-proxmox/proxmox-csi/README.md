# Proxmox CSI

The [Proxmox CSI plugin](https://github.com/sergelogvinov/proxmox-csi-plugin) lets Kubernetes use disks of the Proxmox storage pool (`local-enc`) as volumes. The storage class `proxmox-csi` keeps its volumes when the claim is deleted.

## At a glance

| | |
| --- | --- |
| Namespace | `csi-proxmox` |
| Runs in | all 8 environments (Flux set `minimal`) |
| Installed via | HelmRelease, chart from the OCI repository `ghcr.io/sergelogvinov/charts/proxmox-csi-plugin` ([`base/ocirepository.yaml`](base/ocirepository.yaml)); the storage class (pool `local-enc`, `reclaimPolicy: Retain`) is in [`base/helmrelease.yaml`](base/helmrelease.yaml) |
| Flux Kustomization | `proxmox-csi`, depends on `infra-ns` |

## Purpose

Volumes whose disks are created and pinned by Terragrunt, so they survive a full cluster teardown and rebuild. Longhorn is replacing it step by step for ordinary app data; proxmox-csi stays where surviving a rebuild matters. The comparison and when to use which: [`storage.md`](../../../../docs/architecture/storage.md), [ADR 0014](../../../../docs/decisions/0014-longhorn-vs-proxmox-csi.md).

## Where it is used

- **Used by**: no PVC in `k8s/` uses the `proxmox-csi` class any more (the UniFi MongoDB and controller volumes moved to Longhorn with kopiur backup). `unifi-controller` and `unifi-mongodb` still list `proxmox-csi` in their Flux `dependsOn`.
- **Depends on**: the Proxmox API. The plugin's credentials are not in this unit: they come from the `proxmox_csi_plugin` module of the environment's `vehagn-k8s` Terragrunt unit (see [`k8s-minor-upgrade.md`](../../../../docs/operations/k8s-minor-upgrade.md#known-issues)). Volumes are placed by the topology labels `region` and `zone` (= Proxmox node) on the nodes.

## Access

Not exposed.

## Updates

- **Chart**: tag and digest in [`base/ocirepository.yaml`](base/ocirepository.yaml). No special Renovate rule: the default flow of [`update-handling.md`](../../../../docs/operations/update-handling.md) applies.

## Operations

| Task | Doc |
| --- | --- |
| A PVC does not bind or a volume is stuck | [`troubleshooting-storage.md`](../../../../docs/troubleshooting/troubleshooting-storage.md) |
| Volumes declared in Terragrunt, import and state | [`terragrunt/README.md`](../../../../terragrunt/README.md), [`troubleshooting-terraform-state.md`](../../../../docs/troubleshooting/troubleshooting-terraform-state.md) |
| Remove a retained volume | [`storage.md`](../../../../docs/architecture/storage.md#reclaimpolicy-retain-and-the-two-step-cleanup-gotcha) |

## Cheat sheet

```sh
flux get ks proxmox-csi --context admin@<env>-homelab
kubectl get pods -n csi-proxmox --context admin@<env>-homelab
kubectl get storageclass proxmox-csi --context admin@<env>-homelab
kubectl get pvc,pv -A --context admin@<env>-homelab | grep proxmox-csi
```

The capacity check and a sample listing from the earlier README follow under [Reference output](#reference-output).

## Upstream

- Source and releases: <https://github.com/sergelogvinov/proxmox-csi-plugin>
- Documentation: <https://github.com/sergelogvinov/proxmox-csi-plugin#readme>

## Reference output

Kept from the earlier README. The listing of persistent volumes is from the time the UniFi apps still used static `proxmox-csi` volumes; it shows the format, not the current state.

### Available storage capacity

Check for Proxmox CSI being connected with Proxmox server properly:

> [!TIP] **TODO**: Command does not provide output initially. Maybe only after first app deployment?

```sh
❯ kubectl get csistoragecapacities -ocustom-columns=CLASS:.storageClassName,AVAIL:.capacity,ZONE:.nodeTopology.matchLabels -A
CLASS               AVAIL         ZONE
proxmox-csi         294945288Ki   map[topology.kubernetes.io/region:iseja-lab topology.kubernetes.io/zone:pve4]
proxmox-csi         310646676Ki   map[topology.kubernetes.io/region:iseja-lab topology.kubernetes.io/zone:pve5]
proxmox-csi         263785996Ki   map[topology.kubernetes.io/region:iseja-lab topology.kubernetes.io/zone:pve1]
```

### Persistent volumes and claims

```sh
❯ kubectl get pvc,pv -A
NAMESPACE   NAME                                          STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
unifi       persistentvolumeclaim/mongodb-data            Bound    pv-mongodb   1024M      RWO            proxmox-csi    <unset>                 23d
unifi       persistentvolumeclaim/unifi-controller-data   Bound    pv-unifi     500M       RWO            proxmox-csi    <unset>                 23d

NAMESPACE   NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS        VOLUMEATTRIBUTESCLASS   REASON   AGE
            persistentvolume/pv-mongodb   1024M      RWO            Retain           Bound    unifi/mongodb-data            proxmox-csi         <unset>                          23d
            persistentvolume/pv-unifi     500M       RWO            Retain           Bound    unifi/unifi-controller-data   proxmox-csi         <unset>                          23d
```
