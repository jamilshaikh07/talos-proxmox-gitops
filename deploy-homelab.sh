#!/usr/bin/env bash

################################################################################
# Talos Proxmox GitOps - Master Deployment Script
#
# This script orchestrates the 3-layer deployment:
# - Layer 1: Infrastructure (Terraform - VMs)
# - Layer 2: Configuration (Ansible - Talos Kubernetes)
# - Layer 3: GitOps (ArgoCD + Applications)
#
# Usage: ./deploy-homelab.sh [--skip-layer1] [--skip-layer2] [--skip-layer3]
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform/proxmox-homelab"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
GITOPS_DIR="${SCRIPT_DIR}/gitops"
KUBECONFIG_PATH="/tmp/talos-homelab-cluster/rendered/kubeconfig"

# Layer control flags
SKIP_LAYER1=false
SKIP_LAYER2=false
SKIP_LAYER3=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-layer1)
            SKIP_LAYER1=true
            shift
            ;;
        --skip-layer2)
            SKIP_LAYER2=true
            shift
            ;;
        --skip-layer3)
            SKIP_LAYER3=true
            shift
            ;;
        --help)
            cat << EOF
Talos Proxmox GitOps - Master Deployment Script

Usage: $0 [OPTIONS]

Options:
  --skip-layer1    Skip Layer 1 (Infrastructure deployment)
  --skip-layer2    Skip Layer 2 (Talos configuration)
  --skip-layer3    Skip Layer 3 (GitOps deployment)
  --help           Show this help message

Layers:
  Layer 1: Infrastructure (Terraform - Talos VMs)
  Layer 2: Configuration (Ansible - Talos Kubernetes)
  Layer 3: GitOps (ArgoCD + Applications)

  NFS: Uses external OMV server at 10.20.0.229 (not managed by this script)

EOF
            exit 0
            ;;
    esac
done

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

log_layer() {
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] LAYER:${NC} $*"
}

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║           TALOS PROXMOX GITOPS DEPLOYMENT                    ║
║                  Single-Click Homelab                        ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."

    local missing_tools=()

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi

    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        missing_tools+=("ansible")
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    # Check talosctl
    if ! command -v talosctl &> /dev/null; then
        missing_tools+=("talosctl")
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them before continuing"
        exit 1
    fi

    log "✓ All prerequisites installed"
}

check_env_vars() {
    log "Checking environment variables..."

    # Map Terraform-style TF_VAR_* exports into the variables this script expects
    if [ -z "${PROXMOX_API_URL:-}" ] && [ -n "${TF_VAR_proxmox_api_url:-}" ]; then
        export PROXMOX_API_URL="${TF_VAR_proxmox_api_url}"
    fi
    if [ -z "${PROXMOX_API_TOKEN_ID:-}" ] && [ -n "${TF_VAR_proxmox_api_token_id:-}" ]; then
        export PROXMOX_API_TOKEN_ID="${TF_VAR_proxmox_api_token_id}"
    fi
    if [ -z "${PROXMOX_API_TOKEN_SECRET:-}" ] && [ -n "${TF_VAR_proxmox_api_token_secret:-}" ]; then
        export PROXMOX_API_TOKEN_SECRET="${TF_VAR_proxmox_api_token_secret}"
    fi

    local missing_vars=()

    if [ -z "${PROXMOX_API_URL:-}" ]; then
        missing_vars+=("PROXMOX_API_URL")
    fi

    if [ -z "${PROXMOX_API_TOKEN_ID:-}" ]; then
        missing_vars+=("PROXMOX_API_TOKEN_ID")
    fi

    if [ -z "${PROXMOX_API_TOKEN_SECRET:-}" ]; then
        missing_vars+=("PROXMOX_API_TOKEN_SECRET")
    fi

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please export them or add to .env file"
        exit 1
    fi

    log "✓ All environment variables set"
}

# Layer 1: Infrastructure
layer1_infrastructure() {
    if [ "$SKIP_LAYER1" = true ]; then
        log_warning "Skipping Layer 1 (Infrastructure)"
        return 0
    fi

    log_layer "Starting Layer 1: Infrastructure Deployment"

    cd "${TERRAFORM_DIR}"

    log "Initializing Terraform..."
    terraform init

    log "Validating Terraform configuration..."
    terraform validate

    log "Planning infrastructure changes..."
    terraform plan -out=tfplan

    log "Applying infrastructure..."
    terraform apply tfplan

    log "Exporting Terraform outputs for Ansible..."
    terraform output -json > "${ANSIBLE_DIR}/terraform-inventory.json"

    log "Generating Ansible inventory from Terraform..."
    python3 "${SCRIPT_DIR}/scripts/generate-ansible-inventory.py"

    log "✅ Layer 1 Complete: Infrastructure deployed"
    echo "VMs Created:"
    terraform output -json all_vms | jq -r 'to_entries[] | "  - \(.value.name): \(.value.type) (MAC: \(.value.mac_address))"' || true

    # Wait for VMs to boot
    log "Waiting for VMs to boot (60 seconds)..."
    sleep 60

    log "Checking VM connectivity..."
    for ip in 10.20.0.40; do
        if ! timeout 300 bash -c "until ping -c 1 $ip &>/dev/null; do sleep 5; done"; then
            log_error "VM $ip is not reachable"
            exit 1
        fi
    done
    log "✓ All VMs are reachable"
}

# Layer 2: Configuration
layer2_configuration() {
    if [ "$SKIP_LAYER2" = true ]; then
        log_warning "Skipping Layer 2 (Configuration)"
        return 0
    fi

    log_layer "Starting Layer 2: Configuration (Talos Kubernetes)"

    cd "${ANSIBLE_DIR}"

    log "Running Ansible configuration (Talos)..."
    if ! ansible-playbook -i inventory.yml playbooks/layer2-configure.yml; then
        log_error "Layer 2 failed - Talos VMs have been cleaned up"
        exit 1
    fi

    log "✅ Layer 2 Complete: Configuration applied"
    echo "  - NFS: Using external OMV server at 10.20.0.229"
    echo "  - Talos Kubernetes cluster ready"
    echo "  - Cilium CNI installed"
    echo "  - Kubeconfig: ${KUBECONFIG_PATH}"
}

# Layer 3: GitOps
layer3_gitops() {
    if [ "$SKIP_LAYER3" = true ]; then
        log_warning "Skipping Layer 3 (GitOps)"
        return 0
    fi

    log_layer "Starting Layer 3: GitOps (ArgoCD + Applications)"

    cd "${ANSIBLE_DIR}"

    log "Running Ansible GitOps deployment..."
    if ! ansible-playbook playbooks/layer3-gitops.yml; then
        log_error "Layer 3 failed - GitOps deployment unsuccessful"
        exit 1
    fi

    log "✅ Layer 3 Complete: GitOps applications deployed"
    echo ""
    echo "ArgoCD Access:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

# Main deployment function
main() {
    print_banner

    log "Starting Talos Proxmox GitOps deployment..."
    echo ""

    check_prerequisites
    check_env_vars

    echo ""
    log_info "Deployment plan:"
    echo "  Layer 1: ${SKIP_LAYER1:-Run} Infrastructure"
    echo "  Layer 2: ${SKIP_LAYER2:-Run} Configuration"
    echo "  Layer 3: ${SKIP_LAYER3:-Run} GitOps"
    echo ""

    # Execute layers
    layer1_infrastructure
    layer2_configuration
    layer3_gitops

    # Final summary
    echo ""
    echo -e "${GREEN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║           DEPLOYMENT COMPLETED SUCCESSFULLY!                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    log "🎉 Full homelab deployment complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Export kubeconfig: export KUBECONFIG=${KUBECONFIG_PATH}"
    echo "  2. Access ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  3. Monitor applications: kubectl get applications -n argocd --watch"
}

# Execute main function
main "$@"
