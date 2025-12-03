terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}
resource "proxmox_vm_qemu" "vm" {
  target_node = var.target_node
  name        = var.vm_name
  onboot      = var.onboot
  clone       = var.clone
  boot        = var.boot_order
  full_clone  = var.full_clone
  agent       = var.agent
  cores       = var.cores
  sockets     = var.sockets
  memory      = var.memory
  balloon     = var.balloon
  scsihw      = var.scsihw
  tags        = var.tags
  vm_state    = var.vm_state

  network {
    id       = 0
    bridge   = var.network_bridge
    model    = var.network_model
    firewall = var.firewall
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = var.storage
          size       = var.disk_size
          cache      = var.disk_cache
          discard    = var.discard
          iothread   = var.iothread
          emulatessd = var.emulatessd
        }
      }
    }
    ide {
      ide0 {
        cloudinit {
          storage = var.cloudinit_storage
        }
      }
    }
  }

  os_type      = var.os_type
  ipconfig0    = var.ipconfig0
  nameserver   = var.nameserver
  searchdomain = var.searchdomain
  ciuser       = var.ciuser
  cipassword   = var.cipassword
  sshkeys      = var.sshkeys 

  serial {
    id   = "0"
    type = "socket"
  }
}
