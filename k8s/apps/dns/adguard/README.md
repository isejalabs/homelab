```sh
cat k8s/apps/dns/adguard/base/users.yaml | \
  kubectl create secret generic users --dry-run=client --from-file=users.yaml=/dev/stdin -o yaml | \
  kubeseal --cert terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/assets/sealed-secrets/certificate/sealed-secrets.cert -o yaml -n dns --merge-into k8s/apps/dns/adguard/base/secret-users.yaml
```