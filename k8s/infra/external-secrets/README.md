# External Secrets & 1password Connect
## Links
- https://www.1password.dev/connect/get-started?method=1password-cli#1password-cli
- https://rcwz.pl/2025-10-13-managing-secrets-with-1password-and-external-secrets/
- [onedr0p's implementation](https://github.com/onedr0p/home-ops/tree/7ea61fe39704cc339c8b29f4375f207ef8ea9d15/kubernetes/apps/external-secrets)
## INSTALL
### Create connection parameter with `op` CLI
#### op connect server create
```sh
$ op connect server create k8s --vaults K8S
Set up a Connect server.
UUID: C4SMSGSK2JEW5KCB2UPP4VGP7Q
Credentials file: /Users/sebi/src/homelab/1password-credentials.json
```
#### op connect token create
```sh
$ op connect token create k8s --server k8s --vault K8S
```
## Daily operations
### Listing secrets in the cluster
```sh
❯ k get -n external-secrets externalsecrets.external-secrets.io
NAME                              STORETYPE            STORE                 REFRESH INTERVAL   STATUS         READY   LAST SYNC
onepassword-connect-credentials   ClusterSecretStore   onepassword-connect   1h0m0s             SecretSynced   True    4m9s
onepassword-connect-token         ClusterSecretStore   onepassword-connect   1h0m0s             SecretSynced   True    4m9s
```
