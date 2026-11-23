# Immich

Immich is the photo and video archive that replaces Lightroom Mobile for phone uploads. This unit is the application (server and machine learning, installed from the official chart), its resource isolation, its route, and its media storage: static NFS volumes on the NAS `fiona` and their claims. The database and Valkey are the unit [`immich-db`](../immich-db/README.md).

## At a glance

| | |
| --- | --- |
| Namespace | `immich` |
| Runs in | `dev`, `qa`, `rebuild` (Flux set `qa-soaking`); `prod` follows with the promotion ([#2149](https://github.com/isejalabs/homelab/issues/2149)), which moves the unit out of that set |
| Installed via | the official Immich Helm chart (`HelmRelease` `immich` from the OCI repository `ghcr.io/immich-app/immich-charts/immich`) plus raw manifests: four static NFS `PersistentVolume`s and their claims (no CSI driver), the `HTTPRoute`, a `PriorityClass`, a `LimitRange` and a `ResourceQuota`; the namespace comes from [`immich-db`](../immich-db/README.md) |
| Flux Kustomization | `immich`, depends on `immich-db` |

## Purpose

Immich becomes the online archive for all family photos and videos, kept on the NAS `fiona` and run in Kubernetes ([#413](https://github.com/isejalabs/homelab/issues/413)). Who owns which media is decided in [ADR 0018](../../../../docs/decisions/0018-media-source-of-truth.md): Immich owns phone uploads, Lightroom Classic owns the existing library, which Immich only reads. This unit runs the application and provides the storage for it, as plain NFS volumes: the database never goes on NFS, it stays on Longhorn ([#2145](https://github.com/isejalabs/homelab/issues/2145)). It is deployed in `dev` and `qa` first, isolated so that it cannot starve other workloads ([#2146](https://github.com/isejalabs/homelab/issues/2146)): `dev` is for development and first tests of the whole stack (small workers, web UI only, at most 10 photos and videos), `qa` for real user scenarios, uploads from the phones and imports from the NAS.

Why the official chart: the choice was made under "Reuse before you build". The official chart is maintained by the Immich project, signed, and small: it installs the server and machine learning as separate Deployments on the bjw-s common library (the same one as `app-template`, which this repository already uses), takes the system settings as a file and leaves the database and Valkey to the cluster, which is what [`immich-db`](../immich-db/README.md) provides. `app-template` would have meant writing both Deployments, their probes and the settings mount by hand; plain manifests the same plus the upkeep. The community manifests listed in [#413](https://github.com/isejalabs/homelab/issues/413) were read as prior art only.

## Where it is used

- **Used by**: the phones (mobile app) and browsers of the household; the [mount test](../../../test/storage/test-nfs-immich-media.yaml) uses the same claims.
- **Depends on**: [`immich-db`](../immich-db/README.md) (the `Cluster` `immich-db` with the secret `immich-db-app` and the service `immich-db-rw`, Valkey as `immich-valkey`; the Flux Kustomization waits for it); the `internal` Gateway and its wildcard Let's Encrypt production certificate ([`gateway`](../../../infra/gateway-api/gateway/README.md)); the kopiur secret component and Longhorn for the machine learning model cache; the TrueNAS side on `fiona` (datasets, NFS exports restricted to the environment's worker nodes, snapshots, borgbackup), which is configured by hand and documented in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md); the nodes' own NFS client (part of the Talos kubelet image, no extension).

## Access

Through the `internal` Gateway, subdomain `immich`; the general scheme is in [`reference/environments.md`](../../../../docs/reference/environments.md#domain-and-naming). The certificate is a Let's Encrypt **production** one in `dev` and `qa`, so the mobile app accepts it. The route has no request timeout (`timeouts.request: 0s`) and the gateway sets no body size limit, so a large video upload is not cut.

| env | URL |
| --- | --- |
| `dev` | [https://dev-immich.dev.iseja.net](https://dev-immich.dev.iseja.net) |
| `qa` | [https://qa-immich.qa.iseja.net](https://qa-immich.qa.iseja.net) |

## Authentication

In `dev` and `qa` (and in the `prod` overlay, which is not registered yet) people sign in with Keycloak, realm `iseja`; the settings, decisions and the account procedure are in [`immich-sso.md`](../../../../docs/identity/immich-sso.md) ([#1768](https://github.com/isejalabs/homelab/issues/1768)). The component [`immich-sso`](../../../components/apps/immich-sso/README.md) adds the OIDC settings and the client secret; `rebuild` has no Keycloak and keeps the **interim** local accounts with a password. In short:

- **Local administrator**: registered at the first start of an instance, password in the password manager. `passwordLogin` stays enabled, so it is also the break-glass. The first visit to a fresh instance asks to register the administrator and anyone who can reach the URL can do that: do it right after the first start, the environments are reachable inside the LAN only.
- **Everyone else** signs in with Keycloak. `autoRegister` is off: an administrator creates each account (the e-mail address of the directory account, a **storage label** equal to the short name of the person, for example `bob`, which puts the uploads into their own folder under the upload dataset, ADR 0018 rule 4), and the first SSO login links it. The shared `household` account owns the external libraries and has no label; it is a local account. The storage template is enabled in the settings ([Settings in git](#settings-in-git)), so every upload follows it from the first one.
- API keys and the mobile app's session are Immich's own and do not depend on Keycloak.

## Updates

- **Immich**: the tags of the two images in [`base/helmrelease.yaml`](base/helmrelease.yaml) (`immich-server` and `immich-machine-learning`, each with its digest). The chart does not follow every Immich release, so the image tags are set explicitly and Renovate tracks them separately from the chart, in one pull request because the two must run the same version ([`pin-versions.json5`](../../../../.github/renovate/pin-versions.json5)). The pull request is never auto-merged. **A new version goes to `qa` first and is the gate for `prod`** ([#2149](https://github.com/isejalabs/homelab/issues/2149)); take a database dump before it, see [`immich-database.md`](../../../../docs/backup/immich-database.md#upgrading).
- **Chart**: the tag and digest of the `OCIRepository` in [`base/ocirepository.yaml`](base/ocirepository.yaml) (`0.13.4` at the time of writing). A chart bump can change the Deployments, so it is read in the pull request like any other.
- **Export paths** are in [`envs/<env>/kustomization.yaml`](envs) and have to stay in step with the dataset names in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md#datasets). The `ENV` placeholder in `base/` is never applied; `dbg`, `head`, `poc` and `src` have no datasets and do not run the unit.

## Operations

- **First start of an instance**: register the administrator ([Authentication](#authentication)), create the accounts with their storage labels, then the external libraries (import paths `/external/library` and `/external/export`, owner `household`, see [ADR 0018](../../../../docs/decisions/0018-media-source-of-truth.md)). Check **Administration > Server stats / Jobs** afterwards that no job queue is stuck.
- **Immich's own database dump** runs daily at 02:00 and keeps the last 14 in `backups/` on the upload dataset on `fiona`. It is explicit in the settings and must stay enabled; it is the second copy next to the dump of [`immich-db`](../immich-db/README.md) ([`immich-database.md`](../../../../docs/backup/immich-database.md)). Check it with the file list under `backups/` of the upload dataset (the newest file is from this night).
- **Media storage**: TrueNAS settings, snapshots, borgbackup, restore checks: [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md); the ACL entry that lets the mapped user read the library and export is under [users and permissions](../../../../docs/operations/immich-media-storage.md#users-and-permissions). Mount and permission check: [`test-nfs-immich-media.yaml`](../../../test/storage/test-nfs-immich-media.yaml), described under [Verify](../../../../docs/operations/immich-media-storage.md#verify).
- **Backup of the volumes**: the NFS volumes are not backed up by kopiur (it snapshots CSI volumes, not NFS): protection is ZFS snapshots and the borgbackup of the `prod` upload dataset on `fiona`. The model cache is regenerable and has no backup either.
- **Monitoring**: nothing in this repository. The namespace, the Deployments and the `HelmRelease` show up in the Kubernetes monitoring of the environment once Checkmk rediscovers the cluster (owner task, in `dev` and `qa`; `prod` and its `prod_k8s` licence headroom come with [#2149](https://github.com/isejalabs/homelab/issues/2149)). Immich can expose Prometheus metrics (`immich.metrics.enabled`, [docs](https://docs.immich.app/features/monitoring)); that is off because no Prometheus runs in the clusters.

### Isolation

Immich must not starve other workloads, in `dev` with workers of 4 GiB (about 3.3 GiB allocatable, mostly in use) as much as in `qa`. Four layers, all in this unit:

| Layer | What | Where |
| --- | --- | --- |
| Per container | requests and limits for the server and machine learning; the database and Valkey have theirs in [`immich-db`](../immich-db/README.md) | [`base/helmrelease.yaml`](base/helmrelease.yaml), `dev` patched in [`envs/dev`](envs/dev/kustomization.yaml) |
| Namespace | a `ResourceQuota` (requests and memory limits, pods, claims) over the whole namespace, which includes the database, and a `LimitRange` with a memory default and a ceiling per container (defaults only for memory: a CPU default would throttle the database) | `base/resourcequota.yaml`, `base/limitrange.yaml` |
| Scheduler | the `PriorityClass` `immich` (value -100, `preemptionPolicy: Never`) on the server and machine learning pods: below every other workload (default 0), so they are scheduled last and preempted first, and never evict anyone. The database and Valkey keep the default priority on purpose | `base/priorityclass.yaml` |
| Application | job concurrency of one or two per job type in the settings; the size test ([#2147](https://github.com/isejalabs/homelab/issues/2147)) raises it deliberately | `immich.configuration.job` in the `HelmRelease` |

| | `qa` | `dev` |
| --- | --- | --- |
| Server | requests 250m, 768Mi; limits 1500m, 3Gi (2Gi was OOMKilled during transcodes and uploads, [#2147](https://github.com/isejalabs/homelab/issues/2147)) | requests 50m, 512Mi; limits 1 CPU, 1536Mi |
| Machine learning | requests 250m, 1Gi; limits 1500m, 3Gi | requests 50m, 512Mi; limits 1 CPU, 1536Mi |
| Quota | requests 2 CPU, 4Gi; memory limits 9Gi | requests 1 CPU, 2560Mi; memory limits 6Gi |
| Largest container | 3Gi | 1536Mi |

Server and machine learning use the `Recreate` strategy: one replica each, the model cache is a ReadWriteOnce volume, and a second pod during an upgrade would count against the quota. An upgrade is a short outage, accepted for `dev` and `qa`; `prod` revisits it ([#2149](https://github.com/isejalabs/homelab/issues/2149)).

### Settings in git

The system settings are a file (`immich.configuration` in the `HelmRelease`, mounted as `IMMICH_CONFIG_FILE`). Immich then **locks the whole settings page in the web UI**; keys that are not in the file keep their default. Change a setting in git. This is what makes the storage template (enabled before the first upload, a later change needs the migration job), the job concurrency and the database dump reproducible. If the proof of concept ([#2309](https://github.com/isejalabs/homelab/issues/2309)) needs to experiment in the UI, remove `immich.configuration` in that environment's overlay for the time of the test and put the result back in git.

### DNS in the pods

Immich's documentation warns about a DNS bug of Alpine-based images when the nodes have a search domain. The Talos nodes do have one (`test.iseja.net`, visible in the pods' `/etc/resolv.conf`), but the current images are not Alpine: the server image is built on Debian or Ubuntu (`immich-app/base-server-prod`) and machine learning on `python:3.13-slim-trixie` (checked in the Dockerfiles of v3.4.2), so no `dnsConfig` is set. The pods resolve `immich-db-rw`, `immich-valkey` and `immich-machine-learning` (see the test in [#2146](https://github.com/isejalabs/homelab/issues/2146)).

## Cheat sheet

```sh
# the application, the volumes and their binding
kubectl --context admin@dev-homelab get pods,pvc,helmrelease,httproute,resourcequota -n immich
kubectl --context admin@dev-homelab describe resourcequota immich -n immich

# the logs of the server (the migration at first start, the jobs, the external library scans)
kubectl --context admin@dev-homelab logs -n immich deploy/immich-server --tail=100

# why a pod cannot mount (export hosts, firewall, name resolution)
kubectl --context admin@dev-homelab -n immich describe pod <pod>

# check that the Flux Kustomization is ready
flux --context admin@dev-homelab get ks immich
```

## Media volumes

Static `PersistentVolume`s, pinned to their claims by `claimRef` and `volumeName` (`storageClassName: ""`, so no dynamic provisioning), reclaim policy `Retain`, mounted with `nfsvers=4.1,hard,noatime,nconnect=4`. The server is `fiona.home.iseja.net`. The capacity on the objects is nominal; the limit is the ZFS quota of the dataset.

| Claim | Mode | Mount in the Immich pod | Path on `fiona` (`prod`; non-prod in the runbook) |
| --- | --- | --- | --- |
| `immich-upload` | read-write | `/data` (`IMMICH_MEDIA_LOCATION`, the default) | `natascha1/data/srv/immich/upload` (non-prod: the directory `upload` of `fiona2/gamma/srv/immich/<env>`) |
| `immich-cache` | read-write | `/data/thumbs` with `subPath: thumbs` and `/data/encoded-video` with `subPath: encoded-video` | the directory `cache` of `fiona2/gamma/srv/immich/<env>` (all environments) |
| `immich-library` | **read-only** | a fixed path such as `/external/library`, set as the import path of the external library | the live Lightroom library `natascha1/data/media/Pictures/orig` (non-prod: the folder `orig` of a ZFS clone of `natascha1/data/media` under `natascha1/gamma/srv/immich-copy/<env>`) |
| `immich-export` | **read-only** | a fixed path such as `/external/export`, the second external library | the folder `natascha1/data/media/Pictures/export`, written from the Mac (non-prod: the folder `export` of the clone) |

The export path of a volume is always `/mnt/<path>`. The full dataset table, per environment, is in [`immich-media-storage.md`](../../../../docs/operations/immich-media-storage.md#datasets); the videos-only library is not part of the proof of concept yet.

How the pods use them (all in [`base/helmrelease.yaml`](base/helmrelease.yaml)):

- The pods run as **UID `10004`** and **GID `20002`**, the `immich` account (central user management) and its group `fs.media-rw`. The NFS shares map every client to them (`all_squash`), so this only keeps what `ls` shows consistent. The images run as non-root without changes.
- The upload volume is mounted at `/data` and the cache volume twice on top of it, with `subPath: thumbs` and `subPath: encoded-video`. The two external libraries are mounted with `readOnly: true` at `/external/library` and `/external/export`, and **never at another path later**: Immich stores the path of every asset, a moved path is a deleted asset plus a new one.
- Immich writes a hidden `.immich` file into each of its folders and reports a missing mount; `IMMICH_IGNORE_MOUNT_CHECK_ERRORS` is not set and must not be.
- The unit is not in `prod` yet: with [#2149](https://github.com/isejalabs/homelab/issues/2149) it moves from `qa-soaking` into `prod`'s own composition ([`envs/prod`](envs/prod/kustomization.yaml) already has the real paths).

## Upstream

- Homepage and documentation: <https://immich.app/>
- Source and releases: <https://github.com/immich-app/immich>
- Kubernetes install notes: <https://docs.immich.app/install/kubernetes>
