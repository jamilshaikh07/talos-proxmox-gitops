variable "target_node" {
  type        = string
  description = "The target Proxmox node where the VM will be created"
  default     = "fatimavilla"
}

variable "vm_name" {
  type        = string
  description = "The name of the VM"
}

variable "onboot" {
  type    = bool
  default = true
}

variable "clone" {
  type = string
}

variable "boot_order" {
  type    = string
  default = "order=scsi0;ide0"
}

variable "full_clone" {
  type    = bool
  default = true
}

variable "agent" {
  type    = number
  default = 0
}

variable "cores" {
  type    = number
  default = 1
}

variable "sockets" {
  type    = number
  default = 1
}

variable "cpu" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "memory" {
  type    = number
  default = 1024
}

variable "balloon" {
  type    = number
  default = 0
}

variable "scsihw" {
  type    = string
  default = "virtio-scsi-pci"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_model" {
  type    = string
  default = "virtio"
}

variable "firewall" {
  type    = bool
  default = true
}

variable "storage" {
  type = string
}

variable "disk_size" {
  type    = string
  default = "25G"
}

variable "disk_cache" {
  type    = string
  default = "writeback"
}

variable "discard" {
  type    = bool
  default = false
}

variable "iothread" {
  type    = bool
  default = true
}

variable "emulatessd" {
  type    = bool
  default = true
}

variable "cloudinit_storage" {
  type = string
}

variable "os_type" {
  type    = string
  default = "cloud-init"
}

variable "ipconfig0" {
  type = string
}

variable "ciuser" {
  type    = string
  default = "ubuntu"
}

variable "cipassword" {
  type    = string
  default = "as"
}

variable "sshkeys" {
  type        = string
  sensitive   = true
  description = "SSH public key(s) for cloud-init. Pass via TF_VAR_sshkeys or terraform.tfvars"
  default     = ""
}

variable "nameserver" {
  type    = string
  default = ""
}

variable "searchdomain" {
  type    = string
  default = ""
}

variable "tags" {
}

variable "vm_state" {
  type    = string
  default = "running"
}