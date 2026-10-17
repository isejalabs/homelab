# Zigbee2MQTT

Zigbee2MQTT runs in the dev cluster first, using the ConBee II passed through to the `dev-work-01` worker on Proxmox host `pve1`. The pod is pinned to the worker's Kubernetes hostname label, `dev-work-01.test.iseja.net`. The application continues to use the existing MQTT broker at `mqtt.home.iseja.net`. The app-template Helm release generates an HTTPRoute for the frontend on the internal Gateway; in dev its hostname is `dev-zigbee2mqtt.dev.iseja.net`.

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
kubectl exec -i -n zigbee2mqtt zigbee2mqtt-data-migration -- tar -C /data -xpf - < "$SOURCE_ARCHIVE"
kubectl exec -n zigbee2mqtt zigbee2mqtt-data-migration -- ls -la /data
```

Confirm `configuration.yaml` and `database.db` are present before starting Zigbee2MQTT. Delete the migration pod after the copy and before starting Zigbee2MQTT; Longhorn's RWO PVC cannot be mounted by the app and migration pod at the same time.

The app's persistent data PVC is `10Mi`; the shared storage component still uses `STORAGE_CAPACITY` for the Kopia cache, so Zigbee2MQTT sets it to `1Gi` and overrides only its PVC request. Logs are written below `/app/data/log` by default, which is mounted as a `1Gi` `emptyDir`. The pod's local ephemeral-storage limit is also `1Gi` (with a `64Mi` request), and logs are discarded when the pod is replaced. Zigbee2MQTT also writes logs to stdout, visible with `kubectl logs`. Kubernetes enforces local ephemeral-storage limits through kubelet measurement and pod eviction when supported by the node's filesystem/runtime; this is not a filesystem-level hard quota.

The cut-over sequence is:

1. Test broker DNS, network access, and credentials from a short-lived MQTT client pod before touching the coordinator. Use the `zigbee2mqtt-mqtt` Secret and a temporary topic under `zigbee2mqtt/` for a publish/subscribe round trip.
2. With the Home Assistant add-on stopped and ConBee II attached to `dev-work-01`, start Kubernetes Zigbee2MQTT at `ghcr.io/koenkk/zigbee2mqtt:1.39.1`. The `-1` suffix in `1.39.1-1` is the Home Assistant add-on revision; the upstream image uses `1.39.1`. Verify it loads existing devices/groups and connects to MQTT.
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

The deployment is intentionally registered only in dev while the module USB-passthrough change is reviewed and the migration is tested. Promote it to QA and production after the dev cutover is verified.
