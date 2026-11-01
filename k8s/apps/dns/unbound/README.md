# Unbound

[Unbound](https://github.com/NLnetLabs/unbound) is a validating, recursive DNS resolver. Here it is the upstream of AdGuard for the internal domain and answers everything else by recursing from the root servers.

## At a glance

| | |
| --- | --- |
| Namespace | `unbound` |
| Runs in | `head`, `prod`, `qa`, `rebuild` (Flux set `optional`) |
| Installed via | Raw manifests (Deployment, Service) with the `madnuttah/unbound` image; configuration from ConfigMaps generated from [`base/config/`](base/config/) |
| Flux Kustomization | `unbound`, no `dependsOn` |

## Purpose

Resolves names without a third-party resolver and validates DNSSEC, and sends the internal zone `iseja.net` to its real authoritative servers (a stub zone to the root nameserver LXCs, which are outside this repo). The `iseja.net` zone is exempt from validation. Details of the chain and of the probes that keep it independent of the internet: [`network.md`](../../../../docs/architecture/network.md#dns-adguard--unbound).

## Where it is used

- **Used by**: [`adguard`](../adguard/README.md), which forwards `iseja.net` and the reverse zones to it.
- **Depends on**: the root nameservers of `iseja.net` (`10.7.2.10`, `10.7.2.12`, outside this repo) for the internal zone, and the internet for everything else. It tolerates an outage: `serve-expired` and `prefetch` keep answering from cache, and the probes use `localhost` so a line outage never restarts the pod.

## Access

DNS on port 53 (TCP and UDP) at two fixed load balancer addresses per environment, `10.8.<env-id>.8` and `10.8.<env-id>.11`. Also published as `unbound.<env>.iseja.net` (with the prefix, `qa-unbound.qa.iseja.net`). No web UI.

| env | Addresses |
| --- | --- |
| `head` | `10.8.1.8`, `10.8.1.11` |
| `qa` | `10.8.2.8`, `10.8.2.11` |
| `rebuild` | `10.8.7.8`, `10.8.7.11` |
| `prod` | `10.8.8.8`, `10.8.8.11` |

The access control in [`base/config/conf.d/access-control.conf`](base/config/conf.d/access-control.conf) decides who may ask.

## Updates

- **Image**: `docker.io/madnuttah/unbound` with tag and digest in [`base/deployment.yaml`](base/deployment.yaml). Only the multi-arch `-quic` tags are allowed (the per-architecture tags crash on other nodes).
- **Staged**: `base/` (all environments except `prod`) takes new releases at once; `prod` pins its own copy in [`envs/prod/deployment.yaml`](envs/prod/deployment.yaml) and only gets a PR when a release is 3 days old: [Staged rollout: unbound](../../../../docs/operations/update-handling.md#staged-rollout-unbound).

## Operations

| Task | Doc |
| --- | --- |
| Unbound restarts (CrashLoopBackOff) while the internet is down | [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md#4-unbound-restarts-crashloopbackoff-while-the-internet-is-down) |
| External names return `SERVFAIL` (DNSSEC) | [`troubleshooting-dns.md`](../../../../docs/troubleshooting/troubleshooting-dns.md#5-external-names-return-servfail-through-unbound-dnssec) |

## Cheat sheet

Replace `<env>` with `head`, `qa`, `rebuild` or `prod`.

```sh
flux get ks unbound --context admin@<env>-homelab
kubectl get pods,svc -n unbound --context admin@<env>-homelab
kubectl logs -n unbound deploy/unbound -f --context admin@<env>-homelab

# validated answer carries the "ad" flag; a bogus one must fail with SERVFAIL
dig @10.8.<env-id>.8 example.org +dnssec
dig @10.8.<env-id>.8 dnssec-failed.org

# the internal zone, answered via the stub zone
dig @10.8.<env-id>.8 <env>.iseja.net NS
```

## Upstream

- Source: <https://github.com/NLnetLabs/unbound>, documentation <https://unbound.docs.nlnetlabs.nl/>
- Image: <https://github.com/madnuttah/unbound-docker>
