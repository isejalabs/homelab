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

Use a non-`prod` environment where Keycloak is registered (`dev`, `qa`, `rebuild`); the script refuses `prod`. `qa` is the environment the comparison asks for. The script needs `kubectl` with the `admin@<env>-homelab` context, `curl`, `jq` and `gum`, and network access to the environment's Keycloak hostname (so run it from a machine on the home network). It stops with an error if the probes are not healthy before the drill starts.

Drain the node of the database primary, with the proposed planned-drain target:

```sh
scripts/keycloak-drain-drill.sh -e qa --target 300
```

It prints where the pods and images are, asks for confirmation, records a short healthy baseline, cordons and drains the node (`--node <node>` picks another one, for example the node of `keycloak-0` when the two run apart), waits until both probes have been healthy again for five consecutive samples, uncordons the node and prints the report. Press Ctrl-C to abort: the node is uncordoned again on exit.

For an unplanned failure or another kind of disturbance, only measure and cause the disturbance yourself (for example a hard stop of the worker VM with [`proxmox-vm-power.md`](proxmox-vm-power.md), after [`node-lifecycle.md`](node-lifecycle.md) made sure that is acceptable in that environment):

```sh
scripts/keycloak-drain-drill.sh -e qa --observe --target 900
```

It changes nothing, starts measuring and ends once it has seen an outage and the probes are healthy again (or after `--timeout`, default 1800 seconds). The data goes to a directory under `$TMPDIR` (`--out <dir>` to choose one): probe logs, `events.json`, `pods.json`, `drain.txt`, `preflight.txt` and `report.txt`. Attach `report.txt` and `preflight.txt` to the issue.

Repeat the drain at least three times before relying on the number: a single run is what produced the 10.5 minutes.

## What the probes measure

Two probes run every `--interval` seconds (default 2) against the hostname from the `Keycloak` resource, both on the `master` realm:

| Probe | Request | Healthy | Meaning |
| --- | --- | --- | --- |
| `discovery` | `GET /realms/master/.well-known/openid-configuration` | `200` | The Keycloak pod answers through the Gateway |
| `login` | `POST /realms/master/protocol/openid-connect/token` (client `admin-cli`, password grant, a user that does not exist) | `400` with error `invalid_grant` ("Invalid user credentials") | The token endpoint looked up the user and rejected the credentials, which is what a failed login looks like; `5xx`, another body or no answer means logins fail |

The `login` probe sends a made-up user, so nothing is created and no real account is touched or locked. It is meant to exercise the login path without credentials in the script; whether a lookup of an unknown user reaches the database on every attempt is an assumption this drill should confirm: if the database is down while Keycloak is up, the `login` window should start and end with the database, and the `discovery` window should be shorter. A different result in the first run means the probe must be changed before the numbers are trusted. The resolution of every window is the probe interval, and it is measured from this machine, so a problem in the network path counts as an outage.

## Read the result

The report has three parts: the outage windows per probe, a timeline, and the verdict (exit code `2` when the `login` outage exceeds `--target`). In the timeline, offsets are seconds after the start of the drill, and these are the phases to separate:

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

No measurement has been recorded yet. Add one row per run (environment, date, disturbance, node, preflight decisions, login outage total and longest, target, verdict) and link the issue comment that holds the `report.txt`.

| Date | Environment | Disturbance | Login outage (total / longest) | Target | Verdict |
| --- | --- | --- | --- | --- | --- |
| first drill, reported in [#1937](https://github.com/isejalabs/homelab/issues/1937) | not recorded | Drain | about 10.5 min | none | disturbed by disk pressure and cold image pulls |
