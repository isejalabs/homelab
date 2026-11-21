set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['sh', '-euo', 'pipefail', '-c']

[arg('env', long='env', short='e', pattern='dbg|dev|head|poc|prod|qa|rebuild|src')]
[confirm('Bootstrap cluster for environment "' + env + '"? [y|N]')]
[doc('Bootstrap a Talos & Kubernetes cluster end-to-end')]
cluster env: (core env) (apps env)
    just log info "Deployed cluster" "env" "{{ env }}"

# Apply the core configuration: namespaces, personal credentials and CRDs, in this order
[private]
core env: && (namespaces env) (personal-credentials env) (crds env)
    just log info "Running stage..." "stage" "{{ recipe_name() }}"

# Create the namespaces (step of the core stage, also callable on its own)
[private]
namespaces env:
    just logstep "core" "namespace creation"
    if ! kustomize build {{ source_directory() }}/../infra/common/ns/envs/{{ env }} | just bootstrap::kubectl-apply {{ env }}; then
        just log fatal "Failed to create namespaces" "stage" "core"
    fi

# Inject the personal credentials via `op inject` (step of the core stage, also callable on its own)
[private]
personal-credentials env:
    just logstep "core"  "personal credentials injection"
    if ! kustomize build {{ source_directory() }}/kustomize/personal | just template - | just bootstrap::kubectl-apply {{ env }}; then
        just log fatal "Failed to apply personal manifests" "stage" "core"
    fi

# Render and apply the CRDs from the crds helmfile (step of the core stage, also callable on its own)
[private]
crds env:
    just logstep "core" "CRDs installation"
    if ! helmfile -f "{{ source_directory() }}/helmfile/crds" template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | just bootstrap::kubectl-apply {{ env }}; then
        just log fatal "Failed to apply base crds" "stage" "core"
    fi

# Server-side apply the manifests on stdin to the cluster of an environment. The one place in this module that
# knows the kubecontext naming ("admin@<env>-homelab", same as kube_context in scripts/lib/common.sh).
[private]
kubectl-apply env:
    kubectl --context admin@{{ env }}-homelab apply --server-side --force-conflicts -f -

# Install applications
[private]
apps env:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    just logstep "{{ recipe_name() }}" "apps deployment by helmfile"
    if ! helmfile -f "{{ source_directory() }}/helmfile/apps" -e {{ env }} sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"
    fi
