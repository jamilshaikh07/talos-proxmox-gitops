#!/usr/bin/env bash

################################################################################
# Cloud-Init Templates Creator
#
# This script creates both Debian 12 and Ubuntu 24.04 cloud-init templates with:
# - Cloud-init configured
# - User: ubuntu (password: as)
# - SSH key authentication
# - QEMU guest agent
# - Passwordless sudo
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-10.20.0.10}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_NODE="${PROXMOX_NODE:-alif}"
PROXMOX_SSH_PORT="${PROXMOX_SSH_PORT:-22}"
STORAGE="local-lvm"
VM_USERNAME="ubuntu"
VM_PASSWORD="as"

# Debian 12 configuration
DEBIAN_TEMPLATE_NAME="debian12-template"
DEBIAN_TEMPLATE_VM_ID=9002
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
DEBIAN_IMAGE_FILE="debian-12-generic-amd64.qcow2"

# Ubuntu 24.04 configuration
UBUNTU_TEMPLATE_NAME="ubuntu24-template"
UBUNTU_TEMPLATE_VM_ID=9003
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
UBUNTU_IMAGE_FILE="ubuntu-24.04-server-cloudimg-amd64.img"

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

log_section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║           Cloud-Init Templates Creator                        ║
║                                                               ║
║  Creates cloud-init templates with:                          ║
║  • Debian 12 (Bookworm)                                      ║
║  • Ubuntu 24.04 LTS (Noble)                                  ║
║                                                               ║
║  Features:                                                    ║
║  • Cloud-init support                                        ║
║  • QEMU guest agent                                          ║
║  • User: ubuntu (password: as)                               ║
║  • SSH key authentication                                    ║
║  • Passwordless sudo                                         ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check SSH access
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" exit 2>/dev/null; then
        log_error "Cannot SSH to Proxmox server!"
        log_error "Run: ssh-copy-id ${PROXMOX_USER}@${PROXMOX_HOST}"
        exit 1
    fi

    # Check if SSH public key exists
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        log_warning "SSH public key not found at ~/.ssh/id_rsa.pub"
        read -p "Do you want to create an SSH key pair? (yes/no): " create_key
        if [[ "$create_key" == "yes" ]]; then
            ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
            log "✓ SSH key pair created"
        else
            log_error "SSH public key is required for templates"
            exit 1
        fi
    fi

    log "✓ Prerequisites checked"
}

create_debian_template() {
    log_section "Creating Debian 12 Template"

    # Check if template already exists
    local template_exists=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep '${DEBIAN_TEMPLATE_VM_ID}' || echo 'notfound'")

    if [[ "$template_exists" != "notfound" ]]; then
        log_warning "Debian template already exists (ID: ${DEBIAN_TEMPLATE_VM_ID})"
        read -p "Do you want to destroy and recreate it? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            log_info "Destroying existing Debian template..."
            ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
                "qm destroy ${DEBIAN_TEMPLATE_VM_ID}"
        else
            log "Keeping existing Debian template"
            return 0
        fi
    fi

    # Get SSH public key
    local ssh_key=$(cat ~/.ssh/id_rsa.pub)

    log_info "Downloading Debian 12 cloud image and creating template..."

    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" bash << EOF
set -e

cd /var/lib/vz/template/iso

# Download Debian 12 cloud image
rm -f ${DEBIAN_IMAGE_FILE}*
echo "Downloading Debian 12 Bookworm cloud image..."
wget -q --show-progress "${DEBIAN_IMAGE_URL}" -O ${DEBIAN_IMAGE_FILE}

# Install libguestfs-tools if not installed
if ! command -v virt-customize &> /dev/null; then
    echo "Installing libguestfs-tools..."
    apt-get update
    apt-get install -y libguestfs-tools
fi

# Customize the image
echo "Customizing Debian image..."
virt-customize -a ${DEBIAN_IMAGE_FILE} \
    --install qemu-guest-agent \
    --run-command 'systemctl enable qemu-guest-agent' \
    --run-command 'useradd -m -s /bin/bash ${VM_USERNAME} || true' \
    --run-command 'echo "${VM_USERNAME}:${VM_PASSWORD}" | chpasswd' \
    --run-command 'usermod -aG sudo ${VM_USERNAME}' \
    --run-command 'echo "${VM_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-${VM_USERNAME}-nopasswd' \
    --run-command 'chmod 440 /etc/sudoers.d/99-${VM_USERNAME}-nopasswd' \
    --run-command 'mkdir -p /home/${VM_USERNAME}/.ssh' \
    --run-command 'chmod 700 /home/${VM_USERNAME}/.ssh' \
    --run-command 'chown -R ${VM_USERNAME}:${VM_USERNAME} /home/${VM_USERNAME}/.ssh' \
    --ssh-inject ${VM_USERNAME}:string:"${ssh_key}" \
    --run-command 'sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config'

# Create VM
echo "Creating Debian VM..."
qm create ${DEBIAN_TEMPLATE_VM_ID} \
    --name ${DEBIAN_TEMPLATE_NAME} \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --ostype l26

# Import disk
echo "Importing disk..."
qm importdisk ${DEBIAN_TEMPLATE_VM_ID} ${DEBIAN_IMAGE_FILE} ${STORAGE}

# Attach disk as scsi0
qm set ${DEBIAN_TEMPLATE_VM_ID} --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${DEBIAN_TEMPLATE_VM_ID}-disk-0

# Add cloud-init drive
qm set ${DEBIAN_TEMPLATE_VM_ID} --ide2 ${STORAGE}:cloudinit

# Make boot from the image
qm set ${DEBIAN_TEMPLATE_VM_ID} --boot c --bootdisk scsi0

# Add serial console
qm set ${DEBIAN_TEMPLATE_VM_ID} --serial0 socket --vga serial0

# Enable QEMU guest agent
qm set ${DEBIAN_TEMPLATE_VM_ID} --agent enabled=1

# Set DHCP
qm set ${DEBIAN_TEMPLATE_VM_ID} --ipconfig0 ip=dhcp

# Set cloud-init user and password
qm set ${DEBIAN_TEMPLATE_VM_ID} --ciuser ${VM_USERNAME}
qm set ${DEBIAN_TEMPLATE_VM_ID} --cipassword ${VM_PASSWORD}

# Set SSH key
qm set ${DEBIAN_TEMPLATE_VM_ID} --sshkeys <(echo "${ssh_key}")

# Set nameserver
qm set ${DEBIAN_TEMPLATE_VM_ID} --nameserver 8.8.8.8

# Convert to template
echo "Converting to template..."
qm template ${DEBIAN_TEMPLATE_VM_ID}

# Cleanup
rm -f ${DEBIAN_IMAGE_FILE}

echo "✓ Debian template created successfully"
EOF

    log "✓ Debian 12 Bookworm template created (ID: ${DEBIAN_TEMPLATE_VM_ID})"
}

create_ubuntu_template() {
    log_section "Creating Ubuntu 24.04 Template"

    # Check if template already exists
    local template_exists=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep '${UBUNTU_TEMPLATE_VM_ID}' || echo 'notfound'")

    if [[ "$template_exists" != "notfound" ]]; then
        log_warning "Ubuntu template already exists (ID: ${UBUNTU_TEMPLATE_VM_ID})"
        read -p "Do you want to destroy and recreate it? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            log_info "Destroying existing Ubuntu template..."
            ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
                "qm destroy ${UBUNTU_TEMPLATE_VM_ID}"
        else
            log "Keeping existing Ubuntu template"
            return 0
        fi
    fi

    # Get SSH public key
    local ssh_key=$(cat ~/.ssh/id_rsa.pub)

    log_info "Downloading Ubuntu 24.04 cloud image and creating template..."

    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" bash << EOF
set -e

cd /var/lib/vz/template/iso

# Download Ubuntu 24.04 cloud image
rm -f ${UBUNTU_IMAGE_FILE}*
echo "Downloading Ubuntu 24.04 LTS cloud image..."
wget -q --show-progress "${UBUNTU_IMAGE_URL}" -O ${UBUNTU_IMAGE_FILE}

# Install libguestfs-tools if not installed
if ! command -v virt-customize &> /dev/null; then
    echo "Installing libguestfs-tools..."
    apt-get update
    apt-get install -y libguestfs-tools
fi

# Customize the image
echo "Customizing Ubuntu image..."
virt-customize -a ${UBUNTU_IMAGE_FILE} \
    --install qemu-guest-agent \
    --run-command 'systemctl enable qemu-guest-agent' \
    --run-command 'echo "${VM_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-${VM_USERNAME}-nopasswd' \
    --run-command 'chmod 440 /etc/sudoers.d/99-${VM_USERNAME}-nopasswd'

# Create VM
echo "Creating Ubuntu VM..."
qm create ${UBUNTU_TEMPLATE_VM_ID} \
    --name ${UBUNTU_TEMPLATE_NAME} \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --ostype l26

# Import disk
echo "Importing disk..."
qm importdisk ${UBUNTU_TEMPLATE_VM_ID} ${UBUNTU_IMAGE_FILE} ${STORAGE}

# Attach disk as scsi0
qm set ${UBUNTU_TEMPLATE_VM_ID} --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${UBUNTU_TEMPLATE_VM_ID}-disk-0

# Add cloud-init drive
qm set ${UBUNTU_TEMPLATE_VM_ID} --ide2 ${STORAGE}:cloudinit

# Make boot from the image
qm set ${UBUNTU_TEMPLATE_VM_ID} --boot c --bootdisk scsi0

# Add serial console
qm set ${UBUNTU_TEMPLATE_VM_ID} --serial0 socket --vga serial0

# Enable QEMU guest agent
qm set ${UBUNTU_TEMPLATE_VM_ID} --agent enabled=1

# Set DHCP
qm set ${UBUNTU_TEMPLATE_VM_ID} --ipconfig0 ip=dhcp

# Set cloud-init user and password
qm set ${UBUNTU_TEMPLATE_VM_ID} --ciuser ${VM_USERNAME}
qm set ${UBUNTU_TEMPLATE_VM_ID} --cipassword ${VM_PASSWORD}

# Set SSH key
qm set ${UBUNTU_TEMPLATE_VM_ID} --sshkeys <(echo "${ssh_key}")

# Set nameserver
qm set ${UBUNTU_TEMPLATE_VM_ID} --nameserver 8.8.8.8

# Convert to template
echo "Converting to template..."
qm template ${UBUNTU_TEMPLATE_VM_ID}

# Cleanup
rm -f ${UBUNTU_IMAGE_FILE}

echo "✓ Ubuntu template created successfully"
EOF

    log "✓ Ubuntu 24.04 LTS template created (ID: ${UBUNTU_TEMPLATE_VM_ID})"
}

display_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        CLOUD-INIT TEMPLATES CREATION COMPLETE!               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}📊 Templates Created:${NC}"
    echo ""
    echo -e "${CYAN}  Debian 12 (Bookworm):${NC}"
    echo "    • Template ID: ${DEBIAN_TEMPLATE_VM_ID}"
    echo "    • Template Name: ${DEBIAN_TEMPLATE_NAME}"
    echo "    • Storage: ${STORAGE}"
    echo ""
    echo -e "${CYAN}  Ubuntu 24.04 LTS (Noble):${NC}"
    echo "    • Template ID: ${UBUNTU_TEMPLATE_VM_ID}"
    echo "    • Template Name: ${UBUNTU_TEMPLATE_NAME}"
    echo "    • Storage: ${STORAGE}"
    echo ""

    echo -e "${BLUE}🔐 Login Credentials (Both Templates):${NC}"
    echo "  • Username: ${VM_USERNAME}"
    echo "  • Password: ${VM_PASSWORD}"
    echo "  • SSH Key: Configured (your ~/.ssh/id_rsa.pub)"
    echo ""

    echo -e "${BLUE}✨ Features:${NC}"
    echo "  ✓ Cloud-init enabled"
    echo "  ✓ QEMU guest agent installed and enabled"
    echo "  ✓ Passwordless sudo configured"
    echo "  ✓ SSH authentication (password + key)"
    echo "  ✓ DHCP networking"
    echo ""

    echo -e "${BLUE}🚀 Usage Examples:${NC}"
    echo ""
    echo -e "${CYAN}  Clone Debian 12 template:${NC}"
    echo "    qm clone ${DEBIAN_TEMPLATE_VM_ID} <NEW_VM_ID> --name <VM_NAME> --full"
    echo "    qm set <NEW_VM_ID> --ipconfig0 ip=dhcp"
    echo "    qm start <NEW_VM_ID>"
    echo ""
    echo -e "${CYAN}  Clone Ubuntu 24.04 template:${NC}"
    echo "    qm clone ${UBUNTU_TEMPLATE_VM_ID} <NEW_VM_ID> --name <VM_NAME> --full"
    echo "    qm set <NEW_VM_ID> --ipconfig0 ip=dhcp"
    echo "    qm start <NEW_VM_ID>"
    echo ""

    echo -e "${BLUE}💡 Terraform Usage:${NC}"
    echo "  source = \"${DEBIAN_TEMPLATE_NAME}\"  # or \"${UBUNTU_TEMPLATE_NAME}\""
    echo "  clone_template = ${DEBIAN_TEMPLATE_VM_ID}  # or ${UBUNTU_TEMPLATE_VM_ID}"
    echo ""
}

# Main execution
main() {
    print_banner

    # Check which templates to create based on environment variables
    local create_debian=true
    local create_ubuntu=true

    if [[ "${DEBIAN_ONLY:-false}" == "true" ]]; then
        create_ubuntu=false
        log "Creating Debian 12 template only..."
    elif [[ "${UBUNTU_ONLY:-false}" == "true" ]]; then
        create_debian=false
        log "Creating Ubuntu 24.04 template only..."
    else
        log "Starting cloud-init templates creation..."
    fi
    echo ""

    check_prerequisites

    if [[ "$create_debian" == "true" ]]; then
        create_debian_template
    fi

    if [[ "$create_ubuntu" == "true" ]]; then
        create_ubuntu_template
    fi

    display_summary

    log "✅ Template(s) created successfully!"
}

# Run main function
main "$@"
