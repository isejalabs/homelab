---
status: current
---

# Keycloak node-drain availability drill

**Choose a task:** run the drill under [Run the drill](#run-the-drill); judge the result under [Read the result](#read-the-result); decide the replica counts under [Decide the replica counts](#decide-the-replica-counts).

**On this page:** [Overview](#overview) · [Target](#target) · [Before the drill](#before-the-drill) · [Run the drill](#run-the-drill) · [What the probes measure](#what-the-probes-measure) · [Read the result](#read-the-result) · [Decide the replica counts](#decide-the-replica-counts) · [Results](#results)

## Overview

Keycloak runs with one replica and one CloudNativePG instance ([`keycloak.yaml`](../k8s/apps/identity/keycloak/base/keycloak.yaml), [`cluster.yaml`](../k8s/apps/identity/keycloak/base/cluster.yaml): `instances: 1`, `enablePDB: false`), so draining the node that runs them stops both and logins fail until they are back on another node ([ADR 0016](decisions/0016-identity-and-web-sso.md), consequences). The first drill, as reported in the reviews collected in [#1937](https://github.com/isejalabs/homelab/issues/1937), measured a login outage of roughly 10.5 minutes, distorted by worker disk pressure and slow image pulls, so it says little about the design itself. This page is the procedure for repeating the drill under controlled conditions and comparing it with an agreed target, tracked in [#1944](https://github.com/isejalabs/homelab/issues/1944).

The measurement is done by [`scripts/keycloak-drain-drill.sh`](../scripts/keycloak-drain-drill.sh). It probes Keycloak from outside while the node is disturbed and prints the outage windows plus a timeline of the pod events (eviction, image pull, database ready, Keycloak ready), so the result shows where the time went, not only how long it was.

## Target

The drill needs a pass/fail criterion, so the accepted login interruption is stated explicitly. Proposed values, **to be agreed in [#1944](https://github.com/isejalabs/homelab/issues/1944) before the repeat measurement** (change this table when they are agreed):

| Scenario | Proposed maximum login interruption | Reasoning |
| --- | --- | --- |
| Planned node drain (Talos or Kubernetes upgrade) | 5 minutes | The [design plan](plans/2026-10-identity-claude.md) expected 1–3 minutes; 5 minutes leaves a margin and still means new logins only fail briefly while existing application sessions continue |
| Unplanned node failure | 15 minutes | Kubernetes only evicts pods from an unreachable node after the default toleration of 300 seconds (unless the workload sets its own), so most of the budget is spent before a replacement is even scheduled |

A target above what one replica and one instance can deliver is the signal to change the replica counts, see [Decide the replica counts](#decide-the-replica-counts).

## Before the drill

The first measurement was dominated by factors that are not part of the design. Fix or explicitly accept each before repeating it, and write the decision into the result:

- [ ] Worker system disks: enlarged ([#1908](https://github.com/isejalabs/homelab/issues/1908)) or the effect accepted. The script prints `DiskPressure` per node before it starts.
- [ ] Image pulls: an image cache is in place ([#1907](https://github.com/isejalabs/homelab/issues/1907)) or a cold pull is accepted. The script lists, per image of the pods on the node, whether the other nodes report it. A node lists at most 50 images, so "not listed" is a strong hint and not proof.
- [ ] Operator restarts on first start ([#1903](https://github.com/isejalabs/homelab/issues/1903)) fixed, or its effect on this run accepted.
- [ ] The environment is healthy: `kubectl --context admin@<env>-homelab -n keycloak get pods` shows `keycloak-0` and the database `Running`, and the Flux `Kustomization` `keycloak` is `Ready`.
- [ ] A recent database dump exists ([`keycloak-backup-restore.md`](keycloak-backup-restore.md#daily-tasks)): the drill does not touch the data, but a drain is the moment a volume problem would show up.

## Run the drill

Use a non-`prod` environment where Keycloak is registered (`dev`, `qa`, `rebuild`); the script refuses `prod`. `qa` is the environment the comparison asks for. The script needs `kubectl` with the `admin@<env>-homelab` context, `curl`, `jq` and `gum`, and network access to the environment's Keycloak hostname (so run it from a machine on the home network). It stops with an error, before changing anything, if the control plane is not healthy (API server not ready, a node not `Ready`, a `kube-apiserver`, `kube-controller-manager` or `kube-scheduler` pod or a CloudNativePG operator pod not ready) or if the probes are not healthy before the drill starts.

Drain the node of the database primary, with the proposed planned-drain target:

```sh
scripts/keycloak-drain-drill.sh -e qa --target 300
```

It checks the control plane, prints where the pods and images are, asks for confirmation, records a short healthy baseline and drains the node (`--node <node>` picks another one, for example the node of `keycloak-0` when the two run apart). The drain runs in the background with its own `--drain-timeout` (default 900 seconds) while the probes keep measuring, so a drain that stalls or fails does not end the measurement: the script waits until the drain has ended and both probes have been healthy again for five consecutive samples, uncordons the node (retrying for up to five minutes if the API server is unreachable) and prints the report. Press Ctrl-C to abort: a running drain is stopped and the node is uncordoned again on exit.

For an unplanned failure or another kind of disturbance, only measure and cause the disturbance yourself (for example a hard stop of the worker VM with [`proxmox-vm-power.md`](proxmox-vm-power.md), after [`node-lifecycle.md`](node-lifecycle.md) made sure that is acceptable in that environment):

```sh
scripts/keycloak-drain-drill.sh -e qa --observe --target 900
```

It changes nothing, still checks the control plane first, starts measuring and ends once it has seen an outage and the probes are healthy again (or after `--timeout`, default 1800 seconds). The data goes to a directory under `$TMPDIR` (`--out <dir>` to choose one): probe logs, `events.json`, `pods.json`, `drain.txt`, `preflight.txt` and `report.txt`. Attach `report.txt` and `preflight.txt` to the issue.

Repeat the drain at least three times before relying on the number: a single run is what produced the 10.5 minutes.

## What the probes measure

Two probes run every `--interval` seconds (default 2) against the hostname from the `Keycloak` resource, both on the `master` realm:

| Probe | Request | Healthy | Meaning |
| --- | --- | --- | --- |
| `discovery` | `GET /realms/master/.well-known/openid-configuration` | `200` | The Keycloak pod answers through the Gateway |
| `login` | `POST /realms/master/protocol/openid-connect/token` (client `admin-cli`, password grant, a user that does not exist) | `400` with error `invalid_grant` ("Invalid user credentials") | The token endpoint looked up the user and rejected the credentials, which is what a failed login looks like; `5xx`, another body or no answer means logins fail |

The `login` probe sends a made-up user, so nothing is created and no real account is touched or locked. It is meant to exercise the login path without credentials in the script; whether a lookup of an unknown user reaches the database on every attempt is an assumption this drill should confirm: if the database is down while Keycloak is up, the `login` window should start and end with the database, and the `discovery` window should be shorter. A different result in the first run means the probe must be changed before the numbers are trusted. The resolution of every window is the probe interval, and it is measured from this machine, so a problem in the network path counts as an outage.

## Read the result

The report has three parts: the outage windows per probe, a timeline, and the verdict. The exit code is `2` when the `login` outage exceeds `--target`, and `1` when the drain failed or did not finish (the report is still written, but it is not a valid drain measurement; the drain duration and exit status are the first line of the report). In the timeline, offsets are seconds after the start of the drill, and these are the phases to separate:

| Phase | Where to look | Notes |
| --- | --- | --- |
| Eviction and shutdown | `Killing` events and the time until the old pods are gone | CloudNativePG gives PostgreSQL up to `stopDelay` (default 1800 s) to stop and reserves `smartShutdownTimeout` (default 180 s) of it for a smart shutdown, which waits for connected clients such as Keycloak's connection pool; a shutdown that takes minutes shows up here (the Cluster does not set either field today) |
| Scheduling and volume attach | `Scheduled`, then `condition Initialized` of the new pod | A Longhorn volume has to be attached on the new node |
| Image pull | `Pulling` / `Pulled` events, the message contains the pull duration | The factor that dominated the first measurement; the first drill reported a 3 min 55 s pull of the Keycloak image |
| Database ready | `condition Ready` of `keycloak-db-1` (the pod name changes when CloudNativePG recreates the instance) | After this the database accepts connections |
| Keycloak ready | `condition Ready` of `keycloak-0`, after Quarkus has started | After this the `login` window should close |

Pod placement is part of the same exercise: the script warns when `keycloak-0` and the database primary run on the same node, because one drain then interrupts both and the phases add up. Whether that is acceptable, or whether a topology spread or anti-affinity rule is worth adding, is decided with the numbers from this drill, not before.

## Decide the replica counts

Decide `instances` for Keycloak and for the database from the measured result, the [target](#target) and the resource cost (a second Keycloak replica costs about 500 MiB, a second database instance about 512 MiB plus a volume). The comparison in [#1937](https://github.com/isejalabs/homelab/issues/1937) does not recommend a second replica by default.

| Measured | Conclusion |
| --- | --- |
| Within the target | Keep one replica and one instance; record the measurement and the rationale |
| Over the target, the time is Keycloak start and image pull | A second Keycloak replica with spreading helps for Keycloak-only restarts; fixing the image pull may be cheaper |
| Over the target, the time is the database (shutdown, volume attach, start) | A second Keycloak replica does not help: the single database instance stays the failure mode. The option is `instances: 2` for the database (a drain then triggers a switchover), as the ADR already names |

Changing a replica count is a follow-up change of its own. Record the outcome here under [Results](#results) and in ADR 0016 or the plan.

## Results

One row per run (environment, date, disturbance, node, login outage total and longest, target, verdict); link the issue comment that holds the `report.txt`.

| Date | Environment | Disturbance | Login outage (total / longest) | Target | Verdict |
| --- | --- | --- | --- | --- | --- |
| first drill, reported in [#1937](https://github.com/isejalabs/homelab/issues/1937) | not recorded | Drain | about 10.5 min | none | disturbed by disk pressure and cold image pulls |
| 2026-10-29 (run 1) | `qa` | Drain of `qa-work-01` (database primary) | between 15.7 and 19.6 min (still failing at 21:53:16, healthy at 21:57:06; the drain started 21:37:28) | 300 s | not valid: the `qa` API server became unavailable during the drain, so the script aborted and the recovery was not measured |
| 2026-10-29 (run 2) | `qa` | Drain of `qa-work-02` (database primary and `keycloak-0` on the same node) | not recovered within the 30 min timeout (at least 1792 s); Keycloak came back on its own roughly 40–46 min after the start, after four container restarts (not measured by the script) | 300 s | FAIL: the database was ready after 192 s, Keycloak much later |

### Findings of the 2026-10-29 `qa` run

The run is not a valid measurement of the design, but it showed what a repeat has to expect:

- **The drain blocks on Longhorn.** `kubectl drain` evicted `keycloak-db-1` and then retried for minutes on the Longhorn `instance-manager` pod of the node, which a `PodDisruptionBudget` protects while a volume is attached to it. A drain of a node with an attached Longhorn volume is therefore slow by itself, independent of Keycloak.
- **Volume attach failed for about 7.5 minutes** after the database pod was scheduled on `qa-work-02` (`AttachVolume.Attach failed ... Bad response statusCode [500]`), then succeeded. This overlapped the control-plane trouble below.
- **Cold pulls happened** as the preflight predicted: the PostgreSQL image was listed on none of the other nodes; the bootstrap image alone took 1 min 10 s.
- **The `qa` control plane was unstable.** `kube-apiserver` on `qa-ctrl-02` refused connections on port 6443 for about 4.5 minutes from three minutes into the drain, failed its liveness probe with HTTP 500, and `kube-controller-manager` and `kube-scheduler` were restarted; the CloudNativePG operator was at 35 restarts. Whether the drain caused it is not known.
- **Before the next attempt:** check the health of the control plane (the script now refuses to start otherwise) and expect the drain itself to wait for Longhorn. The script was changed after this run: the drain runs in the background so a stalled or failed drain no longer ends the measurement, and the uncordon and the collection of events and pods retry while the API server is unreachable.

### Findings of the second 2026-10-29 `qa` run

The control plane was healthy this time and the drain itself finished after 45 s, so this run measures the recovery, and it shows that Keycloak's own start dominates it:

- **Worst-case placement:** the database primary, `keycloak-0` and the Keycloak Operator all ran on the drained node `qa-work-02` (the preflight warns about this). All three were evicted at once and rescheduled to `qa-work-01`.
- **Database: back after 192 s.** Volume detach and attach took 72 s, both images were already on the node, and the pod was `Ready` at +192 s.
- **Keycloak: not back after 30 minutes, back on its own after roughly 40–46.** Pulling the Keycloak image on `qa-work-01` took 5 min 46 s (cold). The container then never became ready: its startup probe failed about 1200 times, the kubelet killed and restarted it twice (at about +1000 s and +1635 s), and the log only ever reached `Changes detected in configuration. Updating the server image.` That is the Quarkus build step that runs at start when the image is not pre-built; the stock image is started without `--optimized` unless the `Keycloak` resource sets `startOptimized` or uses a custom image ([upstream CRD](https://github.com/keycloak/keycloak-k8s-resources/blob/26.8.1/kubernetes/keycloaks.k8s.keycloak.org-v1.yml)), which fits what was seen. `qa-work-01` was at about 75 % CPU at the time, which makes the build slower. That this build is the whole cause is not proven.
- **Recovery on its own, and a restart for comparison.** `keycloak-0` became ready by itself between about 22:50 and 22:56, after four container restarts, which is outside the script's 30-minute window. Deleting the pod afterwards put it on the quiet `qa-work-02` with the image already cached, and it was `Ready` 67 s after scheduling (21:56:41 to 21:57:48 UTC). So the same start takes a little over a minute on a quiet node with a warm image, and tens of minutes on a busy node with a cold one: the node load and the cold pull, not only the build step, decide whether the startup probe is met.
- **Keycloak Operator in `CrashLoopBackOff`** (8 restarts, startup probe), the known problem of [#1903](https://github.com/isejalabs/homelab/issues/1903), made worse by the same busy node.
- **What it means for the replica decision:** with the current manifests a node drain that moves `keycloak-0` is not a 5-minute event but one where Keycloak may not come back by itself. That is a start-time problem of the Keycloak pod (build at start plus a startup probe that kills it), not something a second database instance or replica fixes, and it has to be fixed before the drain duration says anything about the design.
- **Script bug found:** the exit code and the target comparison were lost because `LOGIN_TOTAL` was set inside the `report | tee` pipeline; fixed.
