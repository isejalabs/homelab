set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['sh', '-euo', 'pipefail', '-c']

[confirm('Bootstrap cluster for environment "' + env + '"? [y|N]')]
[doc('Bootstrap a Talos & Kubernetes cluster end-to-end')]
[arg('env', short='e', long='env', pattern='dbg|dev|head|poc|prod|qa|rebuild|src')]
cluster env: (core env) (apps env)
    just log info "Deployed cluster" "env" "{{ env }}"

# Apply the core configuration (CRDs)
[private]
core env:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    just logstep "{{ recipe_name() }}" "namespace creation"
    if ! kustomize build {{ source_directory() }}/../infra/common/ns/envs/{{env}} | kubectl --context admin@{{env}}-homelab apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to create namespaces" "stage" "{{ recipe_name() }}"
    fi
    just logstep "{{ recipe_name() }}" "CRDs installation"
    if ! helmfile -f "{{ source_directory() }}/helmfile/crds" template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | kubectl --context admin@{{env}}-homelab apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply base crds" "stage" "{{ recipe_name() }}"
    fi

# Install applications
[private]
apps env:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    just logstep "{{ recipe_name() }}" "apps deployment by helmfile"
    if ! helmfile -f "{{ source_directory() }}/helmfile/apps" -e {{env}} sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"
    fi
