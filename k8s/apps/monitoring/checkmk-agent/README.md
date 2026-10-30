# Links

- https://docs.checkmk.com/latest/en/monitoring_kubernetes.html
- [checkmk_kube_agent/deploy/charts/checkmk at main · Checkmk/checkmk_kube_agent](https://github.com/Checkmk/checkmk_kube_agent/tree/main/deploy/charts/checkmk)
- [checkmk_kube_agent/deploy/charts/checkmk/values.yaml](https://github.com/Checkmk/checkmk_kube_agent/blob/main/deploy/charts/checkmk/values.yaml)
- https://checkmk.atlassian.net/wiki/spaces/KB/overview?mode=global
- https://checkmk.atlassian.net/wiki/spaces/KB/pages/88834049/Debugging+Special+Agents+Combined#DebuggingSpecialAgents(Combined)-Kubernetes-k8sspecialagent
- https://github.com/kuhn-ruess/Checkmk-Checks/tree/master/datamover

# INSTALL

adopted from https://docs.checkmk.com/latest/en/monitoring_kubernetes.html

## Helm Chart

### Repo

- https://github.com/Checkmk/checkmk_kube_agent

### values.yaml

see vendor's [values.yaml](https://github.com/Checkmk/checkmk_kube_agent/blob/main/deploy/charts/checkmk/values.yaml) for all possible values

#### homelab repo's version

using kustomize overlays and `HelmChartInflationGenerator`, link with up-to-date used value: [base/helm/helmChart.yaml](https://github.com/isejalabs/homelab/blob/main/k8s/apps/monitoring/checkmk-agent/base/helm/helmChart.yaml)

#### example and maybe outdated version:

```yaml
  clusterCollector:
    resources:
      requests:
        cpu: 30m
        memory: 70Mi
      limits:
        cpu: 100m
        memory: 120Mi

  nodeCollector:
    # collect metrics also on control plane nodes
    tolerations:
      - operator: "Exists"
        effect: "NoSchedule"

    cadvisor:
      resources:
        requests:
          cpu: 15m
          memory: 40Mi
        limits:
          cpu: 100m
          memory: 50Mi

    containerMetricsCollector:
      resources:
        requests:
          cpu: 15m
          memory: 40Mi

        limits:
          cpu: 100m
          memory: 50Mi

    machineSectionsCollector:
      resources:
        requests:
          cpu: 30m
          memory: 25Mi
        limits:
          cpu: 100m
          memory: 30Mi
```

### Kustomize

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# DISABLED: do not prefix name nor do other env.-specific transformations
# components:
#   - ../../../../../components/envs/src

resources:
  - ../../base

helmCharts:
  - name: checkmk
    repo: https://checkmk.github.io/checkmk_kube_agent
    version: 1.6.0
    releaseName: myrelease
    namespace: checkmk-kube-agent
    valuesFile: values.yaml
```

## Setup Secrets in cmk

cf. [Helm output](https://docs.checkmk.com/latest/en/monitoring_kubernetes.html#helm_output) and [Storing the password (token) in Checkmk](https://docs.checkmk.com/latest/en/monitoring_kubernetes.html#token)

### Token (Password)

**Path:** `Setup > General > Passwords` Name: `k8s_dev-homelab_cmk-agent`

```sh
k get secrets -n checkmk-kube-agent -o yaml checkmk-kube-agent-checkmk | yq -r '.data.token | @base64d'
```

#### Refresh the token after a cluster is recreated

A recreated cluster (for example `rebuild`) gets a new service-account token. The password-store entry then holds the old one and the Kubernetes special agent fails on `/version` (Checkmk 2.5 reports `Data from endpoint /version did not have mandatory field 'gitVersion'` with an `Unauthorized` status body, i.e. HTTP 401). Read the new token from the cluster as above and replace it in `Setup > General > Passwords`; the entries are named `k8s-<env>-homelab` (and `prod-checkmk` for `prod`). Then activate the changes. The same applies to a newly deployed agent (the first deployment in an environment).

Two pitfalls, both seen on 2026-10-22/23:

- **Copy the token without the shell's end-of-output marker.** `zsh` prints a `%` after output that has no trailing newline; copied along, it becomes the last character of the token (1331 instead of 1330 characters) and the API answers `401`. Pipe it instead: `kubectl get secret checkmk-kube-agent-checkmk -n checkmk-kube-agent -o jsonpath='{.data.token}' | base64 --decode | pbcopy`. The same goes for the CA (`ca.crt`): it must be the CA of the *current* cluster, a recreated cluster has a new one.
- **Editing the password store alone does not reach the running checks on a Community site.** The scheduled `Check_MK` checks read a snapshot of the password store and the CA bundle (`var/check_mk/core/helper_config/latest/`) that is only rewritten when the core configuration is regenerated, while `cmk -d <host>` reads the live files and already works. After saving the password (and the CA), activate a change that regenerates the core configuration, or run `cmk -O` as the site user, then wait for the next check. Verify with `cmk -d <collector host>` first.

### Certificate

**Path:** `Setup > General > Global settings > Site management > Trusted certificate authorities for SSL`

```sh
k get secrets -n checkmk-kube-agent -o yaml checkmk-kube-agent-checkmk | yq -r '.data."ca.crt" | @base64d'
```

### Test connection

```sh
❯ export MYTOKEN=$(kubectl get secret checkmk-kube-agent-checkmk -n checkmk-kube-agent -o=jsonpath='{.data.token}' | base64 --decode)

❯ curl -k -H "Authorization: Bearer $MYTOKEN" https://dev-cmk-k8s-cluster-collector.dev.iseja.net/metadata | jq
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  2734  100  2734    0     0  88026      0 --:--:-- --:--:-- --:--:-- 88193
{
  "cluster_collector_metadata": {
    "node": "dev-work-02.test.iseja.net",
    "host_name": "checkmk-kube-agent-cluster-collector-86f5787d99-dgspm",
    "container_platform": {
      "os_name": "alpine",
      "os_version": "3.15.6",
      "python_version": "3.10.8",
      "python_compiler": "GCC 10.3.1 20211027"
    },
    "checkmk_kube_agent": {
      "project_version": "1.6.0"
    }
  },
  ...
```

## Create Host Folders

**Path:** `Setup > Hosts > Folder > Create`

### Folders

- k8s
  - piggys (RAW w/ multi-env only)
  - envs (RAW w/ multi-env only)
    - dev
    - qa
    - prod
  - nodes (optional)

### Settings

#### Folder: K8S

different per Edition

##### Ent Ed.

| Setting                         | Value                                           |
| ------------------------------- | ----------------------------------------------- |
| IP Address Family               | `No IP`                                         |
| Checkmk agent / API integration | `Configured API integrations, no Checkmk agent` |

##### RAW Ed.

| Setting                            | Value                                  |
| ---------------------------------- | -------------------------------------- |
| IP Address Family                  | `No IP`                                |
| Piggyback (where option available) | `Always use and expect piggyback data` |

#### Folder: envs

`envs` folder only (sub-folders will derive settings)

| Setting                            | Value                                  |
| ---------------------------------- | -------------------------------------- |
| IP Address Family                  | `No IP`                                |
| Piggyback (where option available) | `Always use and expect piggyback data` |

## Create a cluster-collector piggyback host

**Path:** `Setup > Hosts > Hosts > Create`

| Setting            | Value                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------- |
| Hostname           | `dev-cmk-k8s-cluster-collector.dev.iseja.net`<br>`cmk-k8s-cluster-collector.prod.iseja.net` |
| IP address familie | `No IP` (inherited)                                                                         |
| Piggyback          | `Use piggyback data from other hosts if present`, **not** `Always use and expect piggyback data`: the collector host only sends piggyback data, it never receives any, so "expect" leaves its `Check_MK` services at WARN |

## Dynamic Host Management (Enterprise Ed.)

**Path:** `Setup > Hosts > Dynamic host management > Add connection`

| Setting                 | Value                                                                                                                                              |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Connection ID           | `cmk@dev-homelab`                                                                                                                                  |
| Connection Title        | `cmk@dev-homelab`                                                                                                                                  |
| Restrict source host    | `dev-cmk-k8s-cluster-collector.dev.iseja.net`                                                                                                      |
| Create Hosts in         | `K8S`                                                                                                                                              |
| Delete vanished hosts   | `X`                                                                                                                                                |
| Sync interval           | `5 min` (default `1 min`)                                                                                                                          |
| Only add matching hosts | - `^prod`<br>- `^daemonset_`<br>- `^deployment_`<br>- `^namespace_(.+)`<br>- `^statefulset_`<br>- `^pod_(.+)_unifi`<br>- `.+unifi`<br>- `.+immich` |

## Periodic service discovery

**Path:** `Setup > Services > Discovery rules > Periodic service discovery`

| Value                                      | Setting                       |
| ------------------------------------------ | ----------------------------- |
| Every                                      | `0h33m`                       |
| Automatically update service configuration | `tabula-rasa` or 5x `X` (all) |

## Special agent

**Path:** `Setup > Agents > VM, cloud, container > Kubernetes`

| Setting                               | Value                                                                                                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Description                           | K8S dev                                                                                                                                                                  |
| Cluster name                          | dev-homelab                                                                                                                                                              |
| Token                                 | from password store / `<password ref.>`                                                                                                                                  |
| Endpoint                              | https://dev-homelab-k8s-api.test.iseja.net:6443                                                                                                                          |
| Verify SSL certificate                | `X` (Yes) when using IP for endpoint of                                                                                                                                  |
| Enrich with usage data                | `X` (Yes)                                                                                                                                                                |
| Collector NodePort / Ingress endpoint | `https://dev-cmk-k8s-cluster-collector.dev.iseja.net`                                                                                                                    |
| Verify Certificate                    | `[X]` (Yes)                                                                                                                                                              |
| Collect information about             | [X] Deployments<br>[X] DaemonSets<br>[X] StatefulSets<br>[X] Namespaces<br>[X] Nodes<br>[X] Pods<br>[X] Persistent Volume Claims<br>[X] CronJobs<br>[ ] Pods of CronJobs |
| Monitor namespaces - exclude          | `not-used`                                                                                                                                                               |
| Cluster resource aggregation          | control-plane<br>infra                                                                                                                                                   |
| Import annotations as host labels     | `checkmk-monitoring$`                                                                                                                                                    |
| Condition - Folder                    | `dev-cmk-ingress.dev.iseja.net`                                                                                                                                          |

## Host name translation for piggybacked hosts

**Path:** `Setup > Agents > Agent access rules > Host name translation for piggybacked hosts` Description: `Remove node_<cluster> prefix` Multiple regular expressions:

| Regex            | Replacement |
| ---------------- | ----------- |
| `node_(.+)_(.+)` | `\2`        |

Condition - Folder:

- `K8S/envs

# CONFIGURATION

## Kubernetes node count

Path: `Setup > Services > Service monitoring rules > Kubernetes node count` Description: `K8S node count`

| Setting                                     | Value                                          |
| ------------------------------------------- | ---------------------------------------------- |
| Specify roles of a control plane node       | - master<br>- control_plane<br>- control-plane |
| Minimum number of ready worker nodes        | W: `<3`<br>C: `<2`                             |
| Minimum number of ready control plane nodes | W: `<3`<br>C: `<2`                             |
