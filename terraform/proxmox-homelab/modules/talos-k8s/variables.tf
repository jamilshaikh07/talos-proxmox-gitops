variable "vm_name" {
  type        = string
  description = "The name of the VM"
}
variable "target_node" {
  type        = string
  description = "The target Proxmox node where the VM will be created"
  default     = "ilm"
}

variable "iso" {
  type        = string
  description = "The ISO file to use for the VM"
}

variable "network_bridge" {
  type        = string
  description = "The network bridge to use for the VM"
  default     = "vmbr0"
}

variable "network_model" {
  type        = string
  description = "The network model to use for the VM"
  default     = "virtio"
}

variable "mac_address" {
  type        = string
  description = "Static MAC address for the VM (for DHCP reservation)"
  default     = null
}

variable "firewall" {
  type        = bool
  description = "Enable firewall for the VM"
  default     = false
}

variable "cores" {
  type        = number
  description = "The number of cores for the VM"
  default     = 1
}

variable "sockets" {
  type        = number
  description = "The number of sockets for the VM"
  default     = 1
}

variable "cpu" {
  type        = string
  description = "The CPU type for the VM"
  default     = "host"
}

variable "memory" {
  type        = number
  description = "The amount of memory for the VM"
  default     = 2048
}

variable "storage" {
  type        = string
  description = "The storage to use for the VM"
  default     = "local1TB"
}

variable "disk_size" {
  type        = string
  description = "The size of the disk for the VM"
  default     = "100G"
}

variable "disk_cache" {
  type        = string
  description = "The cache to use for the VM"
  default     = "writeback"
}

variable "discard" {
  type        = bool
  description = "Enable discard for the VM"
  default     = false
}

variable "iothread" {
  type        = bool
  description = "Enable iothread for the VM"
  default     = true
}

variable "emulatessd" {
  type        = bool
  description = "Enable emulatessd for the VM"
  default     = true
}

variable "longhorn_disk_size" {
  type        = string
  description = "The size of the Longhorn data disk (set to empty string to disable)"
  default     = ""
}

variable "longhorn_storage" {
  type        = string
  description = "The storage to use for Longhorn disk"
  default     = "local-lvm"
}

variable "tags" {
  type        = string
  description = "Tags to assign to the VM"
  default     = ""
}

variable "vm_state" {
  type    = string
  default = "running"
}