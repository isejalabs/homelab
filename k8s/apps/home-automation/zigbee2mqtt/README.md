# Zigbee2MQTT

Zigbee2MQTT runs in the dev cluster first, using the ConBee II passed through to `dev-work-01.home.iseja.net` on Proxmox host `pve1`. The application continues to use the existing MQTT broker at `mqtt.home.iseja.net`; broker deployment and public frontend routing are out of scope for this component.

## Setup and migration

Before deploying, create a 1Password item named `zigbee2mqtt` in the `base` environment with `MQTT_USER` and `MQTT_PASSWORD` fields for the existing broker. The `ExternalSecret` reads those fields into the `zigbee2mqtt-mqtt` Kubernetes Secret. Reuse the current broker account if it is still valid, transferring its credentials directly into 1Password; do not put them in this repository, a Kubernetes manifest, or issue/PR comments. Zigbee2MQTT's MQTT settings may currently come from the Home Assistant add-on options rather than `configuration.yaml`, so copy them separately: the v2 configuration migration cannot see add-on options or environment variables.

The current Home Assistant add-on runs Zigbee2MQTT `1.39.1-1`; the Kubernetes image is v2, so treat first startup as a major-version migration. Before cutover, record the add-on options (especially MQTT credentials and serial settings) securely, stop the add-on, and take an independent backup of its complete data directory. Keep `configuration.yaml`, `database.db`, and any other files together. Copy the directory contents into the `zigbee2mqtt` PVC while the HelmRelease is still at zero replicas. Preserve the original backup unchanged for rollback.

The v2 startup automatically migrates supported settings in `configuration.yaml`, makes a versioned configuration backup, and writes migration notes such as `migration-1-to-2.log`. Settings supplied by Home Assistant add-on options or environment variables are not included in that automatic migration; reapply the required ones through the Kubernetes HelmRelease and the 1Password item. Review the migration log and startup logs before considering cutover complete, and check the Home Assistant side for changes called out by the Zigbee2MQTT v2 migration notes. Do not manually change the configuration `version` field.

For the cutover, keep the add-on stopped, move the ConBee II to the Kubernetes worker, and then raise the dev HelmRelease replica count to one. Do not run both instances against the coordinator. Verify that the existing devices/groups load, the MQTT connection authenticates, and Home Assistant discovery behaves as expected before treating the migration as successful. On a failed migration, stop the Kubernetes instance before restoring the original data and coordinator to Home Assistant; never use the v2-migrated directory as a v1 rollback source.

The ConBee II uses the `deconz` adapter type. Its coordinator backup support is limited; keep an independent copy of the existing data directory and verify the ConBee II firmware before cutover.

The deployment is intentionally registered only in dev while the module USB-passthrough change is reviewed and the migration is tested. Promote it to QA and production after the dev cutover is verified.
