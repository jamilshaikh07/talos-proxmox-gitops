# VM Configuration (using DHCP instead of static IPs)
locals {
  # Master nodes configuration
  master_nodes = {
    "talos-cp-01" = {
      target_node = "alif"
      memory      = 8192 # 8GB
      cores       = 2
      storage     = "local-lvm"
      disk_size   = "50G"
      disk_cache  = "writethrough"
      mac_address = "BC:24:11:00:00:01" # Static MAC for DHCP reservation
    }
  }

  # Worker nodes configuration
  worker_nodes = {
    "talos-wk-01" = {
      target_node = "alif"
      memory      = 6144 # 6GB
      cores       = 2
      storage     = "local-lvm"
      disk_size   = "50G"
      disk_cache  = "writeback"
      mac_address = "BC:24:11:00:00:02" # Static MAC for DHCP reservation
    }
    "talos-wk-02" = {
      target_node = "alif"
      memory      = 6144 # 6GB
      cores       = 2
      storage     = "local-lvm"
      disk_size   = "50G"
      disk_cache  = "writeback"
      mac_address = "BC:24:11:00:00:03" # Static MAC for DHCP reservation
    }
  }

  # Combine all nodes
  all_nodes = merge(local.master_nodes, local.worker_nodes)
}

# Dynamic VM creation for all nodes
module "k8s_nodes" {
  source   = "./modules/talos-k8s"
  for_each = local.all_nodes

  vm_name     = each.key
  target_node = each.value.target_node
  iso         = "local:iso/metal-amd64-v1.11.5.iso"
  memory      = each.value.memory
  cores       = each.value.cores
  storage     = each.value.storage
  disk_size   = each.value.disk_size
  mac_address = each.value.mac_address
  tags        = "kubernetes;talos;${contains(keys(local.master_nodes), each.key) ? "controlplane" : "worker"}"
}

# Dynamic outputs for all VMs
output "all_vms" {
  description = "Information about all Talos Kubernetes VMs"
  value = {
    for vm_name, vm_config in local.all_nodes : vm_name => {
      id          = module.k8s_nodes[vm_name].vm_id
      name        = module.k8s_nodes[vm_name].vm_name
      mac_address = module.k8s_nodes[vm_name].vm_mac_address
      target_node = module.k8s_nodes[vm_name].vm_target_node
      state       = module.k8s_nodes[vm_name].vm_state
      type        = contains(keys(local.master_nodes), vm_name) ? "controlplane" : "worker"
      memory      = vm_config.memory
      cores       = vm_config.cores
    }
  }
}

output "controlplane_vms" {
  description = "Information about Talos controlplane VMs only"
  value = {
    for vm_name in keys(local.master_nodes) : vm_name => {
      id          = module.k8s_nodes[vm_name].vm_id
      name        = module.k8s_nodes[vm_name].vm_name
      mac_address = module.k8s_nodes[vm_name].vm_mac_address
      target_node = module.k8s_nodes[vm_name].vm_target_node
      state       = module.k8s_nodes[vm_name].vm_state
    }
  }
}

output "worker_vms" {
  description = "Information about Talos worker VMs only"
  value = {
    for vm_name in keys(local.worker_nodes) : vm_name => {
      id          = module.k8s_nodes[vm_name].vm_id
      name        = module.k8s_nodes[vm_name].vm_name
      mac_address = module.k8s_nodes[vm_name].vm_mac_address
      target_node = module.k8s_nodes[vm_name].vm_target_node
      state       = module.k8s_nodes[vm_name].vm_state
    }
  }
}

output "vm_mac_addresses" {
  description = "MAC addresses of all VMs for router DHCP reservation"
  value = {
    for vm_name in keys(local.all_nodes) : vm_name => module.k8s_nodes[vm_name].vm_mac_address
  }
}