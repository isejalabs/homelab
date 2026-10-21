# Zigbee2MQTT

Zigbee2MQTT talks to a ConBee II coordinator that is passed through to one Kubernetes worker, so it can only run in **one** environment at a time. It is deployed to dev first, where the migration from the legacy instance was tested (`dev-work-01` on Proxmox host `pve1`, node label `dev-work-01.test.iseja.net`), and then moves to prod (`prod-work-01` on `pve1`, `prod-work-01.home.iseja.net`) for good; no other environment registers the app, although every environment has the usual overlay folder. The application uses the existing MQTT broker at `mqtt.home.iseja.net`. The app-template Helm release generates an HTTPRoute for the frontend on the internal Gateway (`dev-zigbee2mqtt.dev.iseja.net` in dev, `zigbee2mqtt.prod.iseja.net` in prod; the hostnames are set in the overlays because the domain replacement does not reach HelmRelease values).

## Setup and migration

Before deploying, create a 1Password item named `zigbee2mqtt` in the `base` environment with `MQTT_USER` and `MQTT_PASSWORD` fields for the existing broker. The `ExternalSecret` reads those fields into the `zigbee2mqtt-mqtt` Kubernetes Secret. Reuse the current broker account if it is still valid, transferring its credentials directly into 1Password; do not put them in this repository, a Kubernetes manifest, or issue/PR comments. Zigbee2MQTT's MQTT settings may currently come from the Home Assistant add-on options rather than `configuration.yaml`, so copy them separately: the v2 configuration migration cannot see add-on options or environment variables.

The current Home Assistant add-on runs Zigbee2MQTT `1.39.1-1`; the Kubernetes image is v2, so treat first startup as a major-version migration. Before cutover, record the add-on options (especially MQTT credentials and serial settings) securely, stop the add-on, and take an independent backup of its complete data directory. Keep `configuration.yaml`, `database.db`, and any other files together. Copy the directory contents into the `zigbee2mqtt` PVC while the HelmRelease is still at zero replicas. Preserve the original backup unchanged for rollback.

The PVC and namespace are created by the dev Flux `zigbee2mqtt` Kustomization. Wait for that Kustomization to reconcile before creating a migration pod; a HelmRelease by itself does not create the PVC because it references an existing claim. Check reconciliation and storage resources with:

```sh
flux get ks zigbee2mqtt -A
kubectl get namespace zigbee2mqtt
kubectl get pvc zigbee2mqtt -n zigbee2mqtt
```

If the namespace or PVC is missing, inspect the Flux Kustomization's `Ready` condition and events first; don't create a replacement PVC by hand. The Flux unit waits for Longhorn before applying the app and its storage component.

Once the PVC is `Bound`, create a temporary pod that mounts it. `SOURCE_ARCHIVE` below must be a private tar archive of the *contents* of the Home Assistant add-on's entire Zigbee2MQTT data directory. Keep the archive outside Git and protect it because it contains the Zigbee network configuration.

```sh
SOURCE_ARCHIVE=/secure/path/z2m-data.tar

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: zigbee2mqtt-data-migration
  namespace: zigbee2mqtt
spec:
  restartPolicy: Never
  containers:
    - name: tools
      image: busybox:1.37
      command: ["sh", "-c", "sleep 1d"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: zigbee2mqtt
YAML

kubectl wait -n zigbee2mqtt --for=condition=Ready pod/zigbee2mqtt-data-migration --timeout=120s
kubectl exec -i -n zigbee2mqtt zigbee2mqtt-data-migration -- tar --no-same-owner -C /data -xzpf - < "$SOURCE_ARCHIVE"
kubectl exec -n zigbee2mqtt zigbee2mqtt-data-migration -- chown -R 1000:1000 /data
kubectl exec -n zigbee2mqtt zigbee2mqtt-data-migration -- ls -la /data
```

`--no-same-owner` keeps the archive's original owner (a UID from the old host) from being applied; `chown -R 1000:1000` then gives the files to the UID/GID the app runs as, so it can write `configuration.yaml`, `database.db`, `state.json` and the other files it updates. Use `-xpf` instead of `-xzpf` for an uncompressed tar. Without the `chown`, the extracted files are owned by `root` and only readable by the app.

Confirm `configuration.yaml` and `database.db` are present before starting Zigbee2MQTT. Delete the migration pod after the copy and before starting Zigbee2MQTT; Longhorn's RWO PVC cannot be mounted by the app and migration pod at the same time.

The app's persistent data PVC is `100Mi`. Its Kopia deduplication cache is separate and set to `2Gi` to accommodate the repository's configured cache budgets; the cache can be regenerated and does not need to match the data PVC. Zigbee2MQTT is configured to log to stdout only, so use `kubectl logs` to inspect output. The pod has a `128Mi` ephemeral-storage limit for container writable layers and runtime logs; Kubernetes enforces this through kubelet measurement and pod eviction when supported by the node's filesystem/runtime, not as a filesystem-level hard quota.

The container runs as UID/GID `1000` with `fsGroup: 1000`; the Kopia mover uses the same identity so restored files remain writable. The coordinator is not mounted as a volume: the main container is privileged and therefore receives a copy of the node's `/dev` entries. Talos creates serial devices as `root:root` with mode `0600`, so the dev Terragrunt unit applies a Talos `UdevRulesConfig` patch (`terragrunt/_envcommon/vehagn-k8s/talos-patches/zigbee-coordinator-udev.yaml`) that sets mode `0666` on the ConBee II (`1cf1:0030`) every time the kernel creates its device node, so the non-root container can open it. The rule has no `GROUP`, because udevd on Talos cannot resolve group IDs. Do not mount `/dev/ttyACM0` itself as a `hostPath`: if the stick re-enumerates while a container is created, containerd creates a directory at that path on the node, which stops the kernel from recreating the device node. After the stick is unplugged or re-enumerates, restart the pod so it sees the new device node and the init container fixes its permissions.

The cut-over sequence is:

1. Test broker DNS, network access, and credentials from a short-lived MQTT client pod before touching the coordinator. Use the `zigbee2mqtt-mqtt` Secret and a temporary topic under `zigbee2mqtt/` for a publish/subscribe round trip.
2. With the Home Assistant add-on stopped and ConBee II attached to `dev-work-01`, temporarily change the dev HelmRelease image tag from `2.14.2` to `1.39.1` and start Kubernetes Zigbee2MQTT. The `-1` suffix in `1.39.1-1` is the Home Assistant add-on revision; the upstream image uses `1.39.1`. Verify it loads existing devices/groups and connects to MQTT. Restore tag `2.14.2` only after stopping v1 and taking the pre-upgrade backup in step 3.
3. Stop the Kubernetes v1 pod by setting the dev HelmRelease replicas to zero and waiting for termination. Create the same temporary migration pod again and back up the PVC before upgrading:

   ```sh
   umask 077
   kubectl exec -n zigbee2mqtt zigbee2mqtt-data-migration -- tar -C /data -cpf - . > /secure/path/z2m-pvc-before-v2.tar
   tar -tf /secure/path/z2m-pvc-before-v2.tar | head
   sha256sum /secure/path/z2m-pvc-before-v2.tar
   kubectl delete pod -n zigbee2mqtt zigbee2mqtt-data-migration
   ```

4. Set the dev HelmRelease image back to v2 (`2.14.2`) and replicas to one. Review Zigbee2MQTT startup output and its v1-to-v2 migration log before declaring the cut-over successful.

The v2 startup automatically migrates supported settings in `configuration.yaml`, makes a versioned configuration backup, and writes migration notes such as `migration-1-to-2.log`. Settings supplied by Home Assistant add-on options or environment variables are not included in that automatic migration; reapply the required ones through the Kubernetes HelmRelease and the 1Password item. Review the migration log and startup logs before considering cutover complete, and check the Home Assistant side for changes called out by the Zigbee2MQTT v2 migration notes. Do not manually change the configuration `version` field.

Keep the Home Assistant add-on stopped throughout the Kubernetes v1 and v2 stages. Do not run both instances against the coordinator. Verify that Home Assistant discovery behaves as expected before treating the migration as successful. On a failed migration, stop the Kubernetes instance before restoring the original data and coordinator to Home Assistant; never use the v2-migrated directory as a v1 rollback source.

The ConBee II uses the `deconz` adapter type. Its coordinator backup support is limited; keep an independent copy of the existing data directory and verify the ConBee II firmware before cutover.

The ConBee II is attached to the VM manually (`qm set <vmid> --usb0 host=1cf1:0030` on `pve1`) because Terraform cannot yet set raw host USB devices; see [isejalabs/terraform-proxmox-talos#292](https://github.com/isejalabs/terraform-proxmox-talos/issues/292). The `usb_devices` entry stays in the unit of the environment that currently has the stick so that Terraform does not try to remove it. The HelmRelease base stays at zero replicas so that no environment starts with an empty data directory (which would create a new Zigbee network); an environment opts in by setting `replicas: 1` in its overlay once its data is imported.

## Promotion to production

Prod is registered with zero replicas and the Talos udev rule (`terragrunt/_envcommon/vehagn-k8s/talos-patches/zigbee-coordinator-udev.yaml`, all workers) but without `usb_devices` and without data, so merging the registration does not touch the running Zigbee network. The cut-over then has a preparation part without downtime and a short downtime part. Use `admin@dev-homelab` and `admin@prod-homelab` as the kubectl contexts.

**Preparation (no downtime)**

1. Apply the prod Talos configuration from `main` (`terragrunt apply` in `terragrunt/prod/eu-central-1/prod/vehagn-k8s`, source its `.envrc` first; exclude the two Flux-owned namespaces as in [isejalabs/terraform-proxmox-talos#264](https://github.com/isejalabs/terraform-proxmox-talos/issues/264)). Check that the udev rule landed: `talosctl -n <prod-work-01 ip> logs udevd` shows no `Unknown group`.
2. Create the temporary migration pod from the setup section in prod (namespace `zigbee2mqtt`, PVC `zigbee2mqtt`), pinned to `prod-work-01` with `runAsUser: 1000`/`fsGroup: 1000`. The prod PVC stays `Pending` (`WaitForFirstConsumer`) and the `zigbee2mqtt` Kustomization reports "in progress" until a pod mounts it, so create the pod first; delete it again after the copy.
3. Pre-seed the prod volume from the running dev instance, which proves the restore and the ownership without a downtime. The live `database.db` may be mid-write; the copy is only a dry run:

   ```sh
   kubectl --context admin@dev-homelab exec -n zigbee2mqtt deploy/zigbee2mqtt -- tar -C /app/data -czpf - . \
     | kubectl --context admin@prod-homelab exec -i -n zigbee2mqtt zigbee2mqtt-data-migration -- tar --no-same-owner -C /data -xzpf -
   kubectl --context admin@prod-homelab exec -n zigbee2mqtt zigbee2mqtt-data-migration -- chown -R 1000:1000 /data
   kubectl --context admin@prod-homelab exec -n zigbee2mqtt zigbee2mqtt-data-migration -- ls -la /data
   ```

4. Take a Longhorn snapshot of the dev volume (it is the rollback source), and keep the dev volume untouched afterwards.

**Cut-over (downtime)**

1. Prepare one commit on `main` (a normal PR) that: sets `replicas: 0` in the dev overlay, removes `usb_devices` from the dev unit, adds `usb_devices = [{ host = "1cf1:0030" }]` to `prod-work-01` and sets `replicas: 1` in the prod overlay. Do not merge it yet.
2. Stop dev: scale the dev deployment down and make sure it stays down (suspend its Kustomization or merge the dev part first). Two instances must never run at the same time (same MQTT topics, one network).
3. Repeat the copy from step 3 above with the stopped dev volume mounted in a migration pod in dev instead of `deploy/zigbee2mqtt` (`tar -C /data -czpf - .`), so the database is consistent, then delete both migration pods.
4. On `pve1`: `qm set 7008134 --delete usb0` (dev VM), then `qm set 7008184 --usb0 host=1cf1:0030` (prod VM) and check `/dev/ttyACM0` in the `talosctl dmesg` output with mode `0666`.
5. Merge the commit from step 1, reconcile the prod Kustomization (`flux reconcile ks zigbee2mqtt -n flux-system --with-source --context admin@prod-homelab`) and watch the pod: it must report the 56 devices, connect to MQTT and start the frontend.
6. Check Home Assistant (entities, one light, one switch automation) and take a kopiur backup in prod on the next schedule.

**Rollback**: scale prod down, move the stick back to the dev VM (`qm set`), scale dev up again; the dev volume was not modified. If Zigbee2MQTT in dev changed the network meanwhile, restore the dev volume from the snapshot taken in step 4.
