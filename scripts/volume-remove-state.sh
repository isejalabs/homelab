#!/bin/sh

# remove state of proxmox volumes to prevent their deletion by a `tofu/terragrunt destroy` command
# this allows re-using them upon re-creating the cluster (needs state import then)
for i in $(terragrunt state list | grep module.volumes.module.proxmox-volume); do terragrunt state rm "$i"; done
