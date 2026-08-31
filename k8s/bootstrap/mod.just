set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap a Talos & Kubernetes cluster end-to-end')]
cluster: core apps

# Apply the core configuration (CRDs)
[private]
core:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! helmfile -f "{{ source_directory() }}/helmfile/crds" template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply base crds" "stage" "{{ recipe_name() }}"
    fi

# Install applications
[private]
apps:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    # if ! helmfile -f "{{ source_directory() }}/helmfile/apps.yaml" sync --hide-notes; then
    if ! helmfile -f "{{ source_directory() }}/helmfile/apps" -e dev diff; then
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"
    fi
