# Cheatsheet

```sh
# tackle `volume "foo" already bound to a different claim`
k patch pv pv-mongodb -p '{"spec":{"claimRef": null}}'
k patch pv pv-unifi -p '{"spec":{"claimRef": null}}'

# see logs of unifi controller
k logs -n unifi -l app=unifi-controller -f
```