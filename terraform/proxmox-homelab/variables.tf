variable "proxmox_api_url" {
  type        = string
  default     = ""
  description = "proxmox_api_url"
}
variable "proxmox_api_token_id" {
  type        = string
  default     = ""
  description = "proxmox_api_token_id"
}
variable "proxmox_api_token_secret" {
  type        = string
  default     = ""
  description = "proxmox_api_token_secret"
}
variable "vm_name" {
  type        = string
  default     = ""
  description = "vm_name"
}
variable "memory" {
  type        = number
  default     = 2048
  description = "memory"
}
variable "cores" {
  type        = number
  default     = 2
  description = "cores"
}
variable "ipconfig0" {
  type        = string
  default     = ""
  description = "ipconfig0"
}
variable "disk_size" {
  type        = string
  default     = "50G"
  description = "disk_size"
}
variable "iso" {
  type        = string
  default     = "local:iso/metal-amd64.iso"
  description = "iso"
}
variable "network_bridge" {
  type        = string
  default     = "vmbr0"
  description = "network_bridge"
}
variable "talos_version" {
  type        = string
  default     = "v1.10.4"
  description = "talos_version"
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Path to SSH public key file for cloud-init VMs"
}

variable "ssh_public_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "SSH public key content. If empty, reads from ssh_public_key_path"
}

variable "talos_iso" {
  type        = string
  default     = "local:iso/metal-amd64-1.12.6.iso"
  description = "Talos ISO to boot for all Talos VMs"
}

variable "cluster_network_bridge" {
  type        = string
  default     = "vmbr2"
  description = "Proxmox bridge used by Talos VMs"
}

variable "cluster_subnet_prefix" {
  type        = string
  default     = "192.168.60"
  description = "IPv4 subnet prefix used for planned Talos node addresses"
}

variable "cluster_mac_prefix" {
  type        = string
  default     = "BC:24:11:00:00"
  description = "First five octets used to derive deterministic VM MAC addresses"
}

variable "control_plane_name" {
  type        = string
  default     = "talos-cp-01"
  description = "Talos control plane VM name"
}

variable "control_plane_target_node" {
  type        = string
  default     = "alif"
  description = "Proxmox node hosting the Talos control plane VM"
}

variable "control_plane_ip_octet" {
  type        = number
  default     = 40
  description = "Last IPv4 octet reserved for the Talos control plane"

  validation {
    condition     = var.control_plane_ip_octet >= 2 && var.control_plane_ip_octet <= 254
    error_message = "control_plane_ip_octet must be between 2 and 254."
  }
}

variable "control_plane_memory" {
  type        = number
  default     = 8192
  description = "Memory in MB assigned to the Talos control plane VM"
}

variable "control_plane_cores" {
  type        = number
  default     = 2
  description = "vCPU cores assigned to the Talos control plane VM"
}

variable "control_plane_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage backing the Talos control plane disk"
}

variable "control_plane_disk_size" {
  type        = string
  default     = "100G"
  description = "Primary disk size for the Talos control plane VM"
}

variable "control_plane_disk_cache" {
  type        = string
  default     = "writethrough"
  description = "Disk cache mode for the Talos control plane VM"
}

variable "control_plane_longhorn_disk_size" {
  type        = string
  default     = ""
  description = "Optional additional disk size for the control plane Longhorn data disk"
}

variable "control_plane_longhorn_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage backing the optional control plane Longhorn disk"
}

variable "control_plane_mac_address" {
  type        = string
  default     = ""
  description = "Explicit MAC address for the Talos control plane VM. Empty uses the deterministic default."
}

variable "worker_target_node" {
  type        = string
  default     = "alif"
  description = "Default Proxmox node hosting Talos worker VMs"
}

variable "worker_count" {
  type        = number
  default     = 1
  description = "Number of Talos worker VMs to manage"

  validation {
    condition     = var.worker_count >= 0
    error_message = "worker_count must be zero or greater."
  }
}

variable "worker_ip_start" {
  type        = number
  default     = 41
  description = "Last IPv4 octet used by the first worker VM"

  validation {
    condition     = var.worker_ip_start >= 2 && var.worker_ip_start <= 254
    error_message = "worker_ip_start must be between 2 and 254."
  }
}

variable "worker_memory" {
  type        = number
  default     = 16384
  description = "Default memory in MB assigned to each Talos worker VM"
}

variable "worker_cores" {
  type        = number
  default     = 4
  description = "Default vCPU cores assigned to each Talos worker VM"
}

variable "worker_storage" {
  type        = string
  default     = "local-lvm"
  description = "Default Proxmox storage backing Talos worker disks"
}

variable "worker_disk_size" {
  type        = string
  default     = "100G"
  description = "Default primary disk size for each Talos worker VM"
}

variable "worker_disk_cache" {
  type        = string
  default     = "writethrough"
  description = "Default disk cache mode for Talos worker VMs"
}

variable "worker_longhorn_disk_size" {
  type        = string
  default     = ""
  description = "Optional additional disk size for each worker Longhorn disk"
}

variable "worker_longhorn_storage" {
  type        = string
  default     = "local-lvm"
  description = "Default Proxmox storage backing optional worker Longhorn disks"
}

variable "worker_overrides" {
  type = map(object({
    target_node        = optional(string)
    memory             = optional(number)
    cores              = optional(number)
    storage            = optional(string)
    disk_size          = optional(string)
    disk_cache         = optional(string)
    longhorn_disk_size = optional(string)
    longhorn_storage   = optional(string)
    planned_ip         = optional(string)
    mac_address        = optional(string)
  }))
  default     = {}
  description = "Per-worker overrides keyed by worker name, for example talos-wk-02"
}
