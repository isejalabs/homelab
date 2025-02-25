# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This is the configuration for Terragrunt, a thin wrapper for Terraform and OpenTofu that helps keep your code DRY and
# maintainable: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration. The root configuration contains settings that are common across all
# components and environments, such as how to configure remote state.
include "root" {
  path = find_in_parent_folders()
}

# Include the envcommon configuration for the component. The envcommon configuration contains settings that are common
# for the component across all environments.
include "envcommon" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/vehagn-k8s.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

# Configure the version of the module to use in this environment. This allows you to promote new versions one
# environment at a time (e.g., qa -> stage -> prod).
terraform {
  # using hard-coded URL instead of envcommon instead, so renevate can deal with it
  source = "git::git@github.com:isejalabs/terraform-proxmox-talos.git?ref=v2.0.1"
}

locals {
  env          = "${include.envcommon.locals.env}"
  root_path    = "${dirname(find_in_parent_folders())}"
  storage_vmid = 9812
  vlan_id      = 108
  ctrl_cpu     = 2
  ctrl_disk_size = 10
  ctrl_ram     = 3072
  work_cpu     = 2
  work_disk_size = 10
  work_ram     = 3072
  cpu_type     = "x86-64-v2-AES"
  domain       = "test.iseja.net"
  datastore_id = "local-enc"
  cilium_path  = "k8s/core/network/cilium"
}

inputs = {

  env = "${local.env}"

  image = {
    version        = "v1.8.4"
    update_version = "v1.8.4" # renovate: github-releases=siderolabs/talos
    schematic      = file("assets/talos/schematic.yaml")
  }

  cluster = {
    # ToDo resolve redudundant implementation
    talos_version   = "v1.8.4"
    name            = "${local.env}-vehagn-tg"
    proxmox_cluster = "iseja-lab"
    endpoint        = "10.7.8.121"
    gateway         = "10.7.8.1"
  }

  nodes = {
    "${local.env}-ctrl-01.${local.domain}" = {
      host_node     = "pve1"
      machine_type  = "controlplane"
      ip            = "10.7.8.121"
      vm_id         = 7008121
      cpu           = "${local.ctrl_cpu}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.ctrl_disk_size}"
      ram_dedicated = "${local.ctrl_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    "${local.env}-ctrl-02.${local.domain}" = {
      host_node     = "pve4"
      machine_type  = "controlplane"
      ip            = "10.7.8.122"
      vm_id         = 7008122
      cpu           = "${local.ctrl_cpu}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.ctrl_disk_size}"
      ram_dedicated = "${local.ctrl_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    "${local.env}-ctrl-03.${local.domain}" = {
      host_node     = "pve3"
      machine_type  = "controlplane"
      ip            = "10.7.8.123"
      vm_id         = 7008123
      cpu           = "${local.ctrl_cpu}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.ctrl_disk_size}"
      ram_dedicated = "${local.ctrl_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    "${local.env}-work-01.${local.domain}" = {
      host_node     = "pve1"
      machine_type  = "worker"
      ip            = "10.7.8.124"
      vm_id         = 7008124
      cpu           = "${local.work_cpu}"
      cpu_type      = "custom-x86-64-v2-AES-AVX"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.work_disk_size}"
      ram_dedicated = "${local.work_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    "${local.env}-work-02.${local.domain}" = {
      host_node     = "pve4"
      machine_type  = "worker"
      ip            = "10.7.8.125"
      vm_id         = 7008125
      cpu           = "${local.work_cpu}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.work_disk_size}"
      ram_dedicated = "${local.work_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
  }

  cilium_values  = "${local.root_path}/../${local.cilium_path}/envs/${local.env}/values.yaml"

  volumes = {
    pv-mongodb = {
      node    = "pve4"
      size    = "500M"
      vmid    = "${local.storage_vmid}"
      storage = "${local.datastore_id}"
    }
  }

}
