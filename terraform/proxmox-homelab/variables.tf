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
