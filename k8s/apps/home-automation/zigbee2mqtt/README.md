# Zigbee2MQTT

Zigbee2MQTT runs in the dev cluster first, using the ConBee II passed through to `dev-work-01.home.iseja.net` on Proxmox host `pve1`. The application continues to use the existing MQTT broker at `mqtt.home.iseja.net`; broker deployment and public frontend routing are out of scope for this component.

## Setup and migration

Before deploying, create a 1Password item named `zigbee2mqtt` in the `base` environment with `MQTT_USER` and `MQTT_PASSWORD` fields for the existing broker. The `ExternalSecret` reads those fields into the `zigbee2mqtt-mqtt` Kubernetes Secret.

The HelmRelease starts with zero replicas so it cannot create a new Zigbee network before its existing data is imported. To migrate the current network, stop Zigbee2MQTT in the Home Assistant VM before giving the ConBee II to the Kubernetes worker. Copy the existing Zigbee2MQTT data directory, including `configuration.yaml` and `database.db`, into the `zigbee2mqtt` PVC, then raise the dev HelmRelease replica count to one. This carries the existing network configuration across; do not start both Zigbee2MQTT instances against the coordinator. Verify the adapter path and MQTT connection in the dev cluster before moving the coordinator or enabling the app in another environment.

The ConBee II uses the `deconz` adapter type. Its coordinator backup support is limited; keep an independent copy of the existing data directory before cutover.

The deployment is intentionally registered only in dev while the module USB-passthrough change is reviewed and the migration is tested. Promote it to QA and production after the dev cutover is verified.
