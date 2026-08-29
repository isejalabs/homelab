## Proxmox CSI


### Cheatsheet

#### Avaliable Storage Capacity

Check for Proxmox CSI being connected with Proxmox server properly:

> [!TIP] **TODO**: Command does not provide output initially. Maybe only after first app deployment?

```sh
❯ kubectl get csistoragecapacities -ocustom-columns=CLASS:.storageClassName,AVAIL:.capacity,ZONE:.nodeTopology.matchLabels -A
CLASS               AVAIL         ZONE
proxmox-csi         294945288Ki   map[topology.kubernetes.io/region:iseja-lab topology.kubernetes.io/zone:pve4]
proxmox-csi         310646676Ki   map[topology.kubernetes.io/region:iseja-lab topology.kubernetes.io/zone:pve5]
proxmox-csi         263785996Ki   map[topology.kubernetes.io/region:iseja-lab topology.kubernetes.io/zone:pve1]
```

#### Persistent Volumes and Claims

```sh
❯ k get pvc,pv -A
NAMESPACE   NAME                                          STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
unifi       persistentvolumeclaim/mongodb-data            Bound    pv-mongodb   1024M      RWO            proxmox-csi    <unset>                 23d
unifi       persistentvolumeclaim/unifi-controller-data   Bound    pv-unifi     500M       RWO            proxmox-csi    <unset>                 23d

NAMESPACE   NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS        VOLUMEATTRIBUTESCLASS   REASON   AGE
            persistentvolume/pv-mongodb   1024M      RWO            Retain           Bound    unifi/mongodb-data            proxmox-csi         <unset>                          23d
            persistentvolume/pv-unifi     500M       RWO            Retain           Bound    unifi/unifi-controller-data   proxmox-csi         <unset>                          23d
```
