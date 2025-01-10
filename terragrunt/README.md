```shell
cd terragrunt/<env>/vehagn-k8s

sops -d credentials.provider.auto.tfvars.sops.json > credentials.provider.auto.tfvars.json

# delete exising talosconfig cluster config (otherwise new config would be suffixed with "-1")
CLUSTER="dev-vehagn-tg"; talosctl config remove ${CLUSTER}

# import talosconfig
talosctl config merge output/talos-config.yaml

# delete exising kubeconfig cluster config (otherwise new config would be suffixed with "-1")
CLUSTER="dev-vehagn-tg"; kubectl config delete-context admin@${CLUSTER}; kubectl config delete-user admin@${CLUSTER}; kubectl config delete-cluster ${CLUSTER}

cp ~/.kube/config ~/.kube/config.bak && KUBECONFIG=~/.kube/config:output/kube-config.yaml kubectl config view --flatten > /tmp/config && mv /tmp/config ~/.kube/config
```