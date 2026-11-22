set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Absorbs leftover arguments and lists the recipes instead, same as in `proxmox/vm.just`.
[private]
default *args:
    {{ just_executable() }} --justfile {{ source_file() }} --list

[doc('List pods that are not healthy (CrashLoopBackOff, Error, Pending, not ready, ...) in all namespaces, without completed jobs; extra arguments go to kubectl, e.g. --context qa')]
list-failed *args:
    kubectl get pods -A -o json {{ args }} | jq -r '
      def age:
        (now - (.metadata.creationTimestamp | fromdate) | floor) as $s
        | if $s >= 86400 then "\($s / 86400 | floor)d\($s % 86400 / 3600 | floor)h"
          elif $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
          elif $s >= 60 then "\($s / 60 | floor)m\($s % 60)s"
          else "\($s)s" end;
      ["NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "AGE", "REASON"],
      (.items[]
        | select(.status.phase != "Succeeded")
        | (.status.containerStatuses // []) as $cs
        | select(.status.phase != "Running" or any($cs[]; .ready | not))
        | [ .metadata.namespace,
            .metadata.name,
            "\([$cs[] | select(.ready)] | length)/\(.spec.containers | length)",
            .status.phase,
            ([$cs[].restartCount] | add // 0),
            age,
            ([$cs[] | .state.waiting.reason // .state.terminated.reason // empty] | join(",")) ])
      | @tsv' | column -t -s "$(printf '\t')"
