# VM Configuration (DHCP reservations are derived from deterministic MAC/IP plans)
locals {
  control_plane_planned_ip = "${var.cluster_subnet_prefix}.${var.control_plane_ip_octet}"
  control_plane_mac_address = var.control_plane_mac_address != "" ? var.control_plane_mac_address : format(
    "%s:%02X",
    var.cluster_mac_prefix,
    1,
  )

  master_nodes = {
    (var.control_plane_name) = {
      target_node        = var.control_plane_target_node
      memory             = var.control_plane_memory
      cores              = var.control_plane_cores
      storage            = var.control_plane_storage
      disk_size          = var.control_plane_disk_size
      disk_cache         = var.control_plane_disk_cache
      longhorn_disk_size = var.control_plane_longhorn_disk_size
      longhorn_storage   = var.control_plane_longhorn_storage
      planned_ip         = local.control_plane_planned_ip
      mac_address        = local.control_plane_mac_address
    }
  }

  worker_names = [for index in range(var.worker_count) : format("talos-wk-%02d", index + 1)]

  worker_nodes = {
    for index, worker_name in local.worker_names : worker_name => {
      target_node = coalesce(
        try(var.worker_overrides[worker_name].target_node, null),
        var.worker_target_node,
      )
      memory = coalesce(
        try(var.worker_overrides[worker_name].memory, null),
        var.worker_memory,
      )
      cores = coalesce(
        try(var.worker_overrides[worker_name].cores, null),
        var.worker_cores,
      )
      storage = coalesce(
        try(var.worker_overrides[worker_name].storage, null),
        var.worker_storage,
      )
      disk_size = coalesce(
        try(var.worker_overrides[worker_name].disk_size, null),
        var.worker_disk_size,
      )
      disk_cache = coalesce(
        try(var.worker_overrides[worker_name].disk_cache, null),
        var.worker_disk_cache,
      )
      longhorn_disk_size = coalesce(
        try(var.worker_overrides[worker_name].longhorn_disk_size, null),
        var.worker_longhorn_disk_size,
      )
      longhorn_storage = coalesce(
        try(var.worker_overrides[worker_name].longhorn_storage, null),
        var.worker_longhorn_storage,
      )
      planned_ip = coalesce(
        try(var.worker_overrides[worker_name].planned_ip, null),
        format("%s.%d", var.cluster_subnet_prefix, var.worker_ip_start + index),
      )
      mac_address = coalesce(
        try(var.worker_overrides[worker_name].mac_address, null),
        format("%s:%02X", var.cluster_mac_prefix, index + 2),
      )
    }
  }

  all_nodes = merge(local.master_nodes, local.worker_nodes)
}

check "worker_ip_range" {
  assert {
    condition     = var.worker_count == 0 || var.worker_ip_start + var.worker_count - 1 <= 254
    error_message = "worker_count and worker_ip_start exceed the available IPv4 host range. Lower worker_count or worker_ip_start."
  }
}

check "control_plane_ip_collision" {
  assert {
    condition     = var.worker_count == 0 || !(var.control_plane_ip_octet >= var.worker_ip_start && var.control_plane_ip_octet <= var.worker_ip_start + var.worker_count - 1)
    error_message = "control_plane_ip_octet overlaps the worker IP range. Choose a different control_plane_ip_octet or worker_ip_start."
  }
}

# Dynamic VM creation for all nodes
module "k8s_nodes" {
  source   = "./modules/talos-k8s"
  for_each = local.all_nodes

  vm_name            = each.key
  target_node        = each.value.target_node
  iso                = var.talos_iso
  memory             = each.value.memory
  cores              = each.value.cores
  storage            = each.value.storage
  disk_size          = each.value.disk_size
  disk_cache         = each.value.disk_cache
  longhorn_disk_size = lookup(each.value, "longhorn_disk_size", "")
  longhorn_storage   = lookup(each.value, "longhorn_storage", "local-lvm")
  mac_address        = each.value.mac_address
  network_bridge     = var.cluster_network_bridge
  tags               = "kubernetes;talos;${contains(keys(local.master_nodes), each.key) ? "controlplane" : "worker"}"
}

# Dynamic outputs for all VMs
output "all_vms" {
  description = "Information about all Talos Kubernetes VMs"
  value = {
    for vm_name, vm_config in local.all_nodes : vm_name => {
      id                  = module.k8s_nodes[vm_name].vm_id
      name                = module.k8s_nodes[vm_name].vm_name
      mac_address         = module.k8s_nodes[vm_name].vm_mac_address
      planned_mac_address = vm_config.mac_address
      planned_ip          = vm_config.planned_ip
      target_node         = module.k8s_nodes[vm_name].vm_target_node
      state               = module.k8s_nodes[vm_name].vm_state
      type                = contains(keys(local.master_nodes), vm_name) ? "controlplane" : "worker"
      memory              = vm_config.memory
      cores               = vm_config.cores
    }
  }
}

output "controlplane_vms" {
  description = "Information about Talos controlplane VMs only"
  value = {
    for vm_name in keys(local.master_nodes) : vm_name => {
      id                  = module.k8s_nodes[vm_name].vm_id
      name                = module.k8s_nodes[vm_name].vm_name
      mac_address         = module.k8s_nodes[vm_name].vm_mac_address
      planned_mac_address = local.master_nodes[vm_name].mac_address
      planned_ip          = local.master_nodes[vm_name].planned_ip
      target_node         = module.k8s_nodes[vm_name].vm_target_node
      state               = module.k8s_nodes[vm_name].vm_state
    }
  }
}

output "worker_vms" {
  description = "Information about Talos worker VMs only"
  value = {
    for vm_name in keys(local.worker_nodes) : vm_name => {
      id                  = module.k8s_nodes[vm_name].vm_id
      name                = module.k8s_nodes[vm_name].vm_name
      mac_address         = module.k8s_nodes[vm_name].vm_mac_address
      planned_mac_address = local.worker_nodes[vm_name].mac_address
      planned_ip          = local.worker_nodes[vm_name].planned_ip
      target_node         = module.k8s_nodes[vm_name].vm_target_node
      state               = module.k8s_nodes[vm_name].vm_state
    }
  }
}

output "vm_mac_addresses" {
  description = "MAC addresses of all VMs for router DHCP reservation"
  value = {
    for vm_name in keys(local.all_nodes) : vm_name => module.k8s_nodes[vm_name].vm_mac_address
  }
}

output "planned_dhcp_reservations" {
  description = "Planned DHCP reservations for Talos nodes"
  value = {
    for vm_name, vm_config in local.all_nodes : vm_name => {
      ip_address  = vm_config.planned_ip
      mac_address = vm_config.mac_address
    }
  }
}