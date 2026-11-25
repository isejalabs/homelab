# Kubernetes pod and job helpers

Wrapped by `just k8s::pods::<recipe>`. `-e`/`--environment <env>` selects the cluster (kubecontext `admin@<env>-homelab`, validated against the repo's environments) and defaults to the current `kubectl` context; `-n`/`--namespace <ns>` limits a recipe to one namespace and defaults to all of them.

| File | Purpose |
| --- | --- |
| [`mod.just`](mod.just) | parent of the `pods` module — `just k8s::<module>::<recipe>` |
| [`pods.just`](pods.just) | the `just` recipe `list-failed` |
| [`pods-list-failed.sh`](pods-list-failed.sh) | lists the pods of all namespaces (or `-n`) that are not Running and fully ready (`CrashLoopBackOff`, `Error`, `Pending`, `ContainerStatusUnknown`, ...) with READY, RESTARTS, AGE and the container reason; completed jobs are left out |

`list-failed` shows a pod only while it is in a bad state: a pod that crashes now and then but is ready at the moment of the call does not appear.
