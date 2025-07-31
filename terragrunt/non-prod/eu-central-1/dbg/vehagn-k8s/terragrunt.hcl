# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This is the configuration for Terragrunt, a thin wrapper for Terraform and OpenTofu that helps keep your code DRY and
# maintainable: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration. The root configuration contains settings that are common across all
# components and environments, such as how to configure remote state.
include "root" {
  path = find_in_parent_folders("root.hcl")
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

# Include the envcommon configuration for the component. The envcommon configuration contains settings that are common
# for the component across all environments.
include "envcommon" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/vehagn-k8s.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

# Configure the version of the module to use in this environment. This allows you to promote new versions one
# environment at a time (e.g., qa -> stage -> prod).
terraform {
  # using hard-coded URL instead of envcommon variable, so renovate can deal with it
  source = "git::git@github.com:isejalabs/terraform-proxmox-talos.git?ref=v2.0.1"
}

locals {
  env            = include.root.inputs.env
  root_path      = "${dirname(find_in_parent_folders("root.hcl"))}"
  storage_vmid   = 9819
  vlan_id        = 108
  ctrl_cpu       = 2
  ctrl_disk_size = 10
  ctrl_ram       = 3072
  work_cpu       = 2
  work_disk_size = 10
  work_ram       = 3072
  domain         = "test.iseja.net"
  cpu_type       = include.envcommon.locals.cpu_type
  datastore_id   = include.envcommon.locals.datastore_id
  cilium_path    = include.envcommon.locals.cilium_path
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
    endpoint        = "10.7.8.191"
    gateway         = "10.7.8.1"
  }

  nodes = {
    "${local.env}-ctrl-01.${local.domain}" = {
      host_node     = "pve1"
      machine_type  = "controlplane"
      ip            = "10.7.8.191"
      vm_id         = 7008191
      cpu           = "${local.ctrl_cpu}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.ctrl_disk_size}"
      ram_dedicated = "${local.ctrl_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    # "${local.env}-ctrl-02.${local.domain}" = {
    #   host_node     = "pve4"
    #   machine_type  = "controlplane"
    #   ip            = "10.7.8.192"
    #   vm_id         = 7008192
    #   cpu           = "${local.ctrl_cpu}"
    #   datastore_id  = "${local.datastore_id}"
    #   ram_dedicated = "${local.ctrl_ram}"
    #   vlan_id       = "${local.vlan_id}"
    #   # update        = true
    # }
    # "${local.env}-ctrl-03.${local.domain}" = {
    #   host_node     = "pve3"
    #   machine_type  = "controlplane"
    #   ip            = "10.7.8.193"
    #   vm_id         = 7008193
    #   cpu           = "${local.ctrl_cpu}"
    #   datastore_id  = "${local.datastore_id}"
    #   ram_dedicated = "${local.ctrl_ram}"
    #   vlan_id       = "${local.vlan_id}"
    #   # update        = true
    # }
    "${local.env}-work-01.${local.domain}" = {
      host_node     = "pve1"
      machine_type  = "worker"
      ip            = "10.7.8.194"
      vm_id         = 7008194
      cpu           = "${local.work_cpu}"
      cpu_type      = "custom-x86-64-v2-AES-AVX"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.work_disk_size}"
      ram_dedicated = 5120
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    "${local.env}-work-02.${local.domain}" = {
      host_node     = "pve4"
      machine_type  = "worker"
      ip            = "10.7.8.195"
      vm_id         = 7008195
      cpu           = "${local.work_cpu}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.work_disk_size}"
      ram_dedicated = "${local.work_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
  }

  cilium_values = "${local.root_path}/../${local.cilium_path}/envs/${local.env}/values.yaml"

  volumes = {
    pv-mongodb = {
      node    = "pve4"
      size    = "500M"
      vmid    = "${local.storage_vmid}"
      storage = "${local.datastore_id}"
    }
  }

}
