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
  source = "git::git@github.com:isejalabs/terraform-proxmox-talos.git?ref=v6.1.0"
}

locals {
  # Reuse the common variables from the root configuration
  env         = include.root.inputs.env
  projectname = include.root.locals.project_name
  root_path   = "${dirname(find_in_parent_folders("root.hcl"))}"

  # Reuse the common variables from the envcommon configuration
  cilium_path         = include.envcommon.locals.cilium_path
  cpu_type            = include.envcommon.locals.cpu_type
  ctrl_cpu            = include.envcommon.locals.ctrl_cpu
  ctrl_disk_size      = include.envcommon.locals.ctrl_disk_size
  ctrl_ram            = include.envcommon.locals.ctrl_ram
  datastore           = include.envcommon.locals.datastore
  dns                 = include.envcommon.locals.dns
  domain              = include.envcommon.locals.domain
  gateway_api_version = include.envcommon.locals.gateway_api_version
  vlan_id             = include.envcommon.locals.vlan_id
  work_cpu            = include.envcommon.locals.work_cpu
  work_disk_size      = include.envcommon.locals.work_disk_size
  work_ram            = 6144

  # Set some values specific to this environment
  storage_vmid = 9812
  on_boot      = true
}

inputs = {

  env = local.env

  image = {
    version        = "v1.12.4"
    update_version = "v1.12.4" # renovate: github-releases=siderolabs/talos
    schematic_path = "assets/talos/schematic.yaml"
  }

  cluster = {
    api_server                   = <<-EOT
      certSANs:
        # Add FQDN for API server access (via VIP)
        - "${local.env}-${local.projectname}-k8s-api.${local.domain}"
    EOT
    extra_manifests = [
      "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${local.gateway_api_version}/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml",
      "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
    ]
    gateway                      = "10.7.8.1"
    gateway_api_version          = local.gateway_api_version
    kubernetes_version           = "v1.34.4" # renovate: github-releases=kubernetes/kubernetes
    kubelet                      = <<-EOT
      extraArgs:
        # https://www.talos.dev/v1.11/kubernetes-guides/configuration/deploy-metrics-server/
        rotate-server-certificates: true
      registerWithFQDN: true
    EOT
    machine_features             = <<-EOT
      # https://www.talos.dev/v1.8/kubernetes-guides/network/deploying-cilium/#known-issues
      hostDNS:
        forwardKubeDNSToHost: false
    EOT
    name                         = "${local.env}-${local.projectname}"
    on_boot                      = local.on_boot
    proxmox_cluster              = "iseja-lab"
    talos_machine_config_version = "v1.12.4" # renovate: github-releases=siderolabs/talos
    vip                          = "10.7.8.120"
  }

  nodes = {
    # "${local.env}-ctrl-01.${local.domain}" = {
    #   host_node     = "pve1"
    #   machine_type  = "controlplane"
    #   ip            = "10.7.8.121"
    #   vm_id         = 7008121
    #   cpu           = local.ctrl_cpu
    #   datastore     = local.datastore
    #   dns           = local.dns
    #   disk_size     = local.ctrl_disk_size
    #   ram_dedicated = local.ctrl_ram
    #   vlan_id       = local.vlan_id
    #   # update        = true
    # }
    # "${local.env}-ctrl-02.${local.domain}" = {
    #   host_node     = "pve4"
    #   machine_type  = "controlplane"
    #   ip            = "10.7.8.122"
    #   vm_id         = 7008122
    #   cpu           = local.ctrl_cpu
    #   datastore     = local.datastore
    #   dns           = local.dns
    #   disk_size     = local.ctrl_disk_size
    #   ram_dedicated = local.ctrl_ram
    #   vlan_id       = local.vlan_id
    #   # update        = true
    # }
    "${local.env}-ctrl-03.${local.domain}" = {
      host_node     = "pve3"
      machine_type  = "controlplane"
      ip            = "10.7.8.123"
      vm_id         = 7008123
      cpu           = local.ctrl_cpu
      datastore     = local.datastore
      dns           = local.dns
      disk_size     = local.ctrl_disk_size
      ram_dedicated = local.ctrl_ram
      vlan_id       = local.vlan_id
      # update        = true
    }
    "${local.env}-work-01.${local.domain}" = {
      host_node     = "pve1"
      machine_type  = "worker"
      ip            = "10.7.8.124"
      vm_id         = 7008124
      cpu           = local.work_cpu
      cpu_type      = local.cpu_type
      datastore     = local.datastore
      dns           = local.dns
      disk_size     = local.work_disk_size
      ram_dedicated = local.work_ram
      vlan_id       = local.vlan_id
      # update        = true
    }
    "${local.env}-work-02.${local.domain}" = {
      host_node     = "pve4"
      machine_type  = "worker"
      ip            = "10.7.8.125"
      vm_id         = 7008125
      cpu           = local.work_cpu
      cpu_type      = local.cpu_type
      datastore     = local.datastore
      dns           = local.dns
      disk_size     = local.work_disk_size
      ram_dedicated = local.work_ram
      vlan_id       = local.vlan_id
      # update        = true
    }
    "${local.env}-work-03.${local.domain}" = {
      host_node     = "pve3"
      machine_type  = "worker"
      ip            = "10.7.8.126"
      vm_id         = 7008126
      cpu           = local.work_cpu
      cpu_type      = local.cpu_type
      datastore     = local.datastore
      dns           = local.dns
      disk_size     = local.work_disk_size
      ram_dedicated = 2048
      vlan_id       = local.vlan_id
      # update        = true
    }
  }

  cilium_values = "${local.root_path}/../${local.cilium_path}/envs/${local.env}/values.yaml"

  volumes = {
    pv-mongodb = {
      node    = "pve4"
      size    = include.envcommon.locals.pv-mongodb_size
      vmid    = local.storage_vmid
      datastore = local.datastore
    }
    pv-unifi = {
      node    = "pve4"
      size    = include.envcommon.locals.pv-unifi_size
      vmid    = local.storage_vmid
      datastore = local.datastore
    }
  }

}
