# Cilium

[Cilium](https://cilium.io/) is the cluster's CNI and replaces kube-proxy. It also implements the Gateway API (the `GatewayClass` `cilium`), hands out load balancer addresses (LB IPAM) and advertises them to the OPNsense routers over BGP.

## At a glance

| | |
| --- | --- |
| Namespace | `kube-system` |
| Runs in | all 8 environments (Flux set `minimal`); installed first by the bootstrap helmfile, then taken over by Flux |
| Installed via | HelmRelease with the `quay.io/cilium/charts/cilium` OCI chart; values in [`base/values.yaml`](base/values.yaml); per environment the BGP cluster config and the `bgp-pool` address pool in `envs/<env>/` |
| Flux Kustomization | `cilium`, no `dependsOn` |

## Purpose

Without it no pod has a network. Specifically here: pod networking and `kubeProxyReplacement` (Talos reaches the API server at `localhost:7445`), the Gateway API implementation behind every `HTTPRoute`, LB IPAM for `LoadBalancer` Services and Gateways, and the BGP control plane that makes those addresses reachable although the nodes sit in a different subnet. Egress gateway is enabled, Hubble and mutual authentication are off. The whole networking story: [`network.md`](../../../../docs/architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement); why BGP and not L2: [ADR 0008](../../../../docs/decisions/0008-cilium-bgp.md).

## Where it is used

- **Used by**: every workload (pod network), every `Gateway` and `LoadBalancer` Service (address from `bgp-pool`, advertised by [`bgp-advertisement.yaml`](base/bgp-advertisement.yaml)), and the [`gateway`](../../gateway-api/gateway/README.md) unit.
- **Depends on**: the OPNsense pair as BGP peers (`10.7.8.2`, `10.7.8.3`, outside this repo) and the Gateway API CRDs from [`gateway-api-crds`](../../gateway-api/gateway-api-crds/). It has no Flux `dependsOn` because it is the first thing everything else needs at bootstrap: the helmfile installs it before Flux reconciles anything.

## Access

Not exposed: no Hubble UI, no Service of its own for people. What it publishes are the addresses of others: each environment's pool `10.8.<env-id>.8` to `.250`, e.g. `.80` for the internal Gateway. The pool table is in [`reference/environments.md`](../../../../docs/reference/environments.md#environment-id).

## Updates

A critical component: a bad bump takes the network down, so the version is never automerged.

- **Pins**: the shared pin is `spec.ref` in [`base/ocirepository.yaml`](base/ocirepository.yaml); `prod`, `poc` and `head` each pin their own copy in `envs/<env>/ocirepository.yaml` so they can differ from `base/`. Read the files for the current versions; they move.
- **Renovate**: every Cilium PR is labeled `updateStrategy:manual`; the allowed range is capped (for Checkmk compatibility), and `head` and `poc` track newer releases as an early warning (`updateStrategy:pinWatch`). See [Non-standard update strategies](../../../../docs/operations/update-handling.md#non-standard-update-strategies) and [`pin-versions.json5`](../../../../.github/renovate/pin-versions.json5).
- **Kubernetes minor upgrades** need a compatible Cilium: [`k8s-minor-upgrade.md`](../../../../docs/operations/k8s-minor-upgrade.md).

## Operations

| Task | Doc |
| --- | --- |
| Pool, BGP peering and what is advertised | [`network.md`](../../../../docs/architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement) |
| Node or cluster rebuild | [`node-lifecycle.md`](../../../../docs/operations/node-lifecycle.md) |

## Cheat sheet

Replace `<env>` with the environment.

```sh
cilium status --wait --context admin@<env>-homelab
kubectl get pods -n kube-system -l k8s-app=cilium --context admin@<env>-homelab

# BGP: sessions to the OPNsense pair, and the routes this node advertises
cilium bgp peers --context admin@<env>-homelab
cilium bgp routes --context admin@<env>-homelab

# address pool and who got which address
kubectl get ciliumloadbalancerippools,ciliumbgppeerconfigs --context admin@<env>-homelab
kubectl get svc -A --context admin@<env>-homelab | grep LoadBalancer
```

## Upstream

- Homepage and documentation: <https://cilium.io/>, <https://docs.cilium.io/>
- Source and releases: <https://github.com/cilium/cilium>
- BGP control plane: <https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane/>

## Reference output

Captured earlier in `prod`; the versions and ages shown are from that day, not current.

The CNI is running properly when you see the following output for the `cilium status` command:

```sh
❯ cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 6, Ready: 6/6, Available: 6/6
DaemonSet              cilium-envoy             Desired: 6, Ready: 6/6, Available: 6/6
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
Containers:            cilium                   Running: 6
                       cilium-envoy             Running: 6
                       cilium-operator          Running: 2
                       clustermesh-apiserver
                       hubble-relay
Cluster Pods:          60/60 managed by Cilium
Helm chart version:    1.18.13+876b611ff5c6
Image versions         cilium             quay.io/cilium/cilium:v1.18.13@sha256:6e6e6a82a6a2a6d0bfe6dd7e36cb0222fa48135ad139ddc979b5c3c841e2db1a: 6
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.36.9-1786864149-07e8503ff34b9190d7bbe4e57d4e185c4ef8b1de@sha256:beccdf3c119f299cf696885188584bbd0531d74bca08096113207999aff95e87: 6
                       cilium-operator    quay.io/cilium/operator-generic:v1.18.13@sha256:2041417ad2ebd8b3e7d80b63dd81810d405fa29f12926ddbe78321a74781993b: 2
```

... and the BGP configuration is applied successfully, when CRDs are installed in the cluster and the configuration applied.

Command to check for cilium's CRDs:

```sh
❯ kubectl get crd | grep cilium
ciliumbgpadvertisements.cilium.io              2026-08-29T16:55:16Z
ciliumbgpclusterconfigs.cilium.io              2026-08-29T16:55:15Z
ciliumbgpnodeconfigoverrides.cilium.io         2026-08-29T16:55:25Z
ciliumbgpnodeconfigs.cilium.io                 2026-08-29T16:55:23Z
ciliumbgppeerconfigs.cilium.io                 2026-08-29T16:55:21Z
ciliumbgppeeringpolicies.cilium.io             2026-08-29T16:55:13Z
ciliumcidrgroups.cilium.io                     2026-08-29T16:55:07Z
ciliumclusterwideenvoyconfigs.cilium.io        2026-08-29T16:55:10Z
ciliumclusterwidenetworkpolicies.cilium.io     2026-08-29T16:55:03Z
ciliumegressgatewaypolicies.cilium.io          2026-08-29T16:55:09Z
ciliumendpoints.cilium.io                      2026-08-29T16:54:56Z
ciliumenvoyconfigs.cilium.io                   2026-08-29T16:55:12Z
ciliumgatewayclassconfigs.cilium.io            2026-08-29T16:55:28Z
ciliumidentities.cilium.io                     2026-08-29T16:54:53Z
ciliuml2announcementpolicies.cilium.io         2026-08-29T16:55:27Z
ciliumloadbalancerippools.cilium.io            2026-08-29T16:55:26Z
ciliumnetworkpolicies.cilium.io                2026-08-29T16:54:58Z
ciliumnodeconfigs.cilium.io                    2026-08-29T16:55:30Z
ciliumnodes.cilium.io                          2026-08-29T16:54:51Z
ciliumpodippools.cilium.io                     2026-08-29T16:54:55Z
```

The applied configuration can be checked with `kubectl get ciliumbgppeerconfigs`:

```sh
❯ kubectl get ciliumbgppeerconfigs
NAME          AGE
cilium-peer   1m
```

Output of `cilium bgp peers`

```sh
❯ cilium bgp peers
Node                          Local AS   Peer AS   Peer Address   Session State   Uptime      Family         Received   Advertised
prod-work-01.home.iseja.net   64528      64520     10.7.8.2       established     81h29m41s   ipv4/unicast   38         3
                              64528      64520     10.7.8.3       established     80h13m42s   ipv4/unicast   17         3
prod-work-02.home.iseja.net   64528      64520     10.7.8.2       established     81h28m51s   ipv4/unicast   38         7
                              64528      64520     10.7.8.3       established     80h13m42s   ipv4/unicast   17         7
prod-work-03.home.iseja.net   64528      64520     10.7.8.2       established     81h28m50s   ipv4/unicast   38         6
                              64528      64520     10.7.8.3       established     80h13m41s   ipv4/unicast   17         6
```

Output of `cilium bgp routes`

```sh
❯ cilium bgp routes
(Defaulting to `available ipv4 unicast` routes, please see help for more options)

Node                          VRouter   Prefix         NextHop   Age          Attrs
prod-work-01.home.iseja.net   64528     10.8.8.80/32   0.0.0.0   238h50m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.83/32   0.0.0.0   238h50m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
prod-work-02.home.iseja.net   64528     10.8.8.11/32   0.0.0.0   238h52m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.20/32   0.0.0.0   39h59m22s    [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.8/32    0.0.0.0   238h52m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.80/32   0.0.0.0   238h52m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.83/32   0.0.0.0   238h52m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.87/32   0.0.0.0   238h52m22s   [{Origin: i} {Nexthop: 0.0.0.0}]
prod-work-03.home.iseja.net   64528     10.8.8.11/32   0.0.0.0   238h55m14s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.53/32   0.0.0.0   238h55m14s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.8/32    0.0.0.0   238h55m14s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.80/32   0.0.0.0   238h55m14s   [{Origin: i} {Nexthop: 0.0.0.0}]
                              64528     10.8.8.83/32   0.0.0.0   238h55m14s   [{Origin: i} {Nexthop: 0.0.0.0}]
```


Alternatively to the `cilium` command, you can check for the CNI being ready by checking the status of the cilium pods in the `kube-system` namespace.

```sh
kubectl get pods -n kube-system -l k8s-app=cilium
```
