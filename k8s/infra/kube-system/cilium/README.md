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
❯ k get crd | grep cilium
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
❯ k get ciliumbgppeerconfigs
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
k get pods -n kube-system -l k8s-app=cilium
```
