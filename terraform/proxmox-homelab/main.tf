# # Ubuntu VM for NFS Server (Large storage for persistent volumes)
# module "ubuntu-nfs" {
#   source = "./modules/proxmox-vm"

#   vm_name           = "ubuntu-nfs"
#   target_node       = "alif"
#   clone             = "ubuntu-temp"
#   memory            = 2048
#   cores             = 2
#   storage           = "local-lvm"
#   cloudinit_storage = "local-lvm"
#   disk_size         = "600G" # Large storage for Kubernetes persistent volumes
#   tags              = "nfs;ubuntu;storage"
#   onboot            = true
#   agent             = 1

#   # Static IP configuration for NFS server
#   ipconfig0  = "ip=10.20.0.44/24,gw=10.20.0.1"
#   ciuser     = "ubuntu"
#   cipassword = "as"
# }

# # Output for NFS VM
# output "nfs_vm_info" {
#   description = "NFS VM information"
#   value = {
#     id   = module.ubuntu-nfs.vm_id
#     name = module.ubuntu-nfs.vm_name
#   }
# }