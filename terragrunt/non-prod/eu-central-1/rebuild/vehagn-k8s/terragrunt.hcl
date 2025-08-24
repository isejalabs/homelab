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
  source = "git::git@github.com:isejalabs/terraform-proxmox-talos.git?ref=v2.1.0"
}

locals {
  # Reuse the common variables from the root configuration
  env            = include.root.inputs.env
  root_path      = "${dirname(find_in_parent_folders("root.hcl"))}"

  # Reuse the common variables from the envcommon configuration
  cilium_path    = include.envcommon.locals.cilium_path
  cpu_type       = include.envcommon.locals.cpu_type
  ctrl_cpu       = include.envcommon.locals.ctrl_cpu
  ctrl_disk_size = include.envcommon.locals.ctrl_disk_size
  ctrl_ram       = include.envcommon.locals.ctrl_ram
  datastore_id   = include.envcommon.locals.datastore_id
  domain         = include.envcommon.locals.domain
  vlan_id        = include.envcommon.locals.vlan_id
  work_cpu       = include.envcommon.locals.work_cpu
  work_disk_size = include.envcommon.locals.work_disk_size
  work_ram       = include.envcommon.locals.work_ram
  
  # Set some values specific to this environment
  storage_vmid   = 9817
}

inputs = {

  env = "${local.env}"

  image = {
    version        = "v1.10.6"
    update_version = "v1.10.6" # renovate: github-releases=siderolabs/talos
    schematic      = file("assets/talos/schematic.yaml")
  }

  cluster = {
    # ToDo resolve redudundant implementation
    talos_version   = "v1.10.6"
    name            = "${local.env}-vehagn-tg"
    proxmox_cluster = "iseja-lab"
    endpoint        = "10.7.8.171"
    gateway         = "10.7.8.1"
  }

  nodes = {
    "${local.env}-ctrl-01.${local.domain}" = {
      host_node     = "pve1"
      machine_type  = "controlplane"
      ip            = "10.7.8.171"
      vm_id         = 7008171
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
      ip            = "10.7.8.172"
      vm_id         = 7008172
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
      ip            = "10.7.8.173"
      vm_id         = 7008173
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
      ip            = "10.7.8.174"
      vm_id         = 7008174
      cpu           = "${local.work_cpu}"
      cpu_type      = "${local.cpu_type}"
      datastore_id  = "${local.datastore_id}"
      disk_size     = "${local.work_disk_size}"
      ram_dedicated = "${local.work_ram}"
      vlan_id       = "${local.vlan_id}"
      # update        = true
    }
    "${local.env}-work-02.${local.domain}" = {
      host_node     = "pve4"
      machine_type  = "worker"
      ip            = "10.7.8.175"
      vm_id         = 7008175
      cpu           = "${local.work_cpu}"
      cpu_type      = "${local.cpu_type}"
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
