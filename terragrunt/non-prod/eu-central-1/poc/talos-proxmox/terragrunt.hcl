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
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/talos-proxmox.hcl"
  # We want to reference the variables from the included config in this configuration, so we expose it.
  expose = true
}

# Configure the version of the module to use in this environment. This allows you to promote new versions one
# environment at a time (e.g., qa -> stage -> prod).
terraform {
  # comment regex overrides terragrunt nonSemVer matching, replacing s/talos-proxmox-v0.0.1/v0.0.3
  # ToDo see #2
  # source = "${include.envcommon.locals.base_source_url}?ref=v5.0.0" # renovate: github-releases=sebiklamar/terraform-modules
  # using hard-coded URL instead of envcommon due to #2
  source = "git::git@github.com:sebiklamar/terraform-modules.git//modules/talos-proxmox?ref=talos-proxmox-v0.0.2"
}

locals {
  env      = include.root.inputs.env
  vlan_id  = 104
  ctrl_cpu = 2
  ctrl_ram = 3072
  work_cpu = 2
  work_ram = 3072
  domain   = "test.iseja.net"
}

inputs = {
  image = {
    version        = "v1.8.1"
    update_version = "v1.10.7" # renovate: github-releases=siderolabs/talos
  }

  cluster = {
    # ToDo resolve redundant def. of a talos version (in contrast to var.image.version)
    talos_version   = "v1.8.1"
    name            = "${local.env}-talos-tg"
    proxmox_cluster = "iseja-lab"
    endpoint        = "10.7.4.111"
    gateway         = "10.7.4.1"
  }

  nodes = {
    "${local.env}-ctrl-01.${local.domain}" = {
      host_node     = "pve2"
      machine_type  = "controlplane"
      ip            = "10.7.4.111"
      vm_id         = 7004111
      vlan_id       = "${local.vlan_id}"
      cpu           = "${local.ctrl_cpu}"
      ram_dedicated = "${local.ctrl_ram}"
      # update        = true
    }
    # "${local.env}-ctrl-02.${local.domain}" = {
    #   host_node     = "pve2"
    #   machine_type  = "controlplane"
    #   ip            = "10.7.4.112"
    #   vm_id         = 7004112
    #   vlan_id       = "${local.vlan_id}"
    #   cpu           = "${local.ctrl_cpu}"
    #   ram_dedicated = "${local.ctrl_ram}"
    #   # update        = true
    # }
    # "${local.env}-ctrl-03.${local.domain}" = {
    #   host_node     = "pve2"
    #   machine_type  = "controlplane"
    #   ip            = "10.7.4.113"
    #   vm_id         = 7004113
    #   vlan_id       = "${local.vlan_id}"
    #   cpu           = "${local.ctrl_cpu}"
    #   ram_dedicated = "${local.ctrl_ram}"
    #   # update        = true
    # }
    "${local.env}-work-01.${local.domain}" = {
      host_node     = "pve2"
      machine_type  = "worker"
      ip            = "10.7.4.114"
      vm_id         = 7004114
      vlan_id       = "${local.vlan_id}"
      cpu           = "${local.work_cpu}"
      ram_dedicated = "${local.work_ram}"
      # update        = true
    }
    "${local.env}-work-02.${local.domain}" = {
      host_node     = "pve2"
      machine_type  = "worker"
      ip            = "10.7.4.115"
      vm_id         = 7004115
      vlan_id       = "${local.vlan_id}"
      cpu           = "${local.work_cpu}"
      ram_dedicated = "${local.work_ram}"
      # update        = true
    }
  }

}