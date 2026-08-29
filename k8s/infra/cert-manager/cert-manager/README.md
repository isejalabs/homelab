## Cert Manager

You can also check the for the certificate beging issued successfully by checking the status of the certificate resource:

```sh
❯ k get certificate -n gateway-api
NAME   READY   SECRET   AGE
cert   True    cert     1m
```


```sh
k describe -n cert-manager secrets

k logs -n cert-manager services/cert-manager -f

k get secrets -n cert-manager cloudflare-api-token -o json | jq -r '.data."api-token" | @base64d'
```