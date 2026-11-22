# Kubernetes pod and job helpers

Wrapped by `just k8s::pods::<recipe>`, run against the current `kubectl` context. The recipes are plain `kubectl | jq` pipelines kept in the `just` files, so there are no scripts here yet; add one next to them once a recipe outgrows a few lines.

| File | Purpose |
| --- | --- |
| [`mod.just`](mod.just) | parent of the `pods` module — `just k8s::<module>::<recipe>` |
| [`pods.just`](pods.just) | the recipe `list-failed`: pods in all namespaces that are not Running and fully ready (`CrashLoopBackOff`, `Error`, `Pending`, `ContainerStatusUnknown`, ...) with READY, RESTARTS, AGE and the container reason; completed jobs are left out; extra arguments go to `kubectl` (`--context qa`) |

`list-failed` shows a pod only while it is in a bad state: a pod that crashes now and then but is ready at the moment of the call does not appear.
