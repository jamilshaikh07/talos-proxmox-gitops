# Talos Proxmox GitOps Makefile - 3-Layer Infrastructure Management
# ====================================================================

# Configuration
TERRAFORM_DIR = terraform/proxmox-homelab
ANSIBLE_DIR = ansible
GITOPS_DIR = gitops
KUBECONFIG_PATH = /tmp/talos-homelab-cluster/rendered/kubeconfig

# Colors for output
GREEN = \033[0;32m
RED = \033[0;31m
YELLOW = \033[1;33m
BLUE = \033[0;34m
CYAN = \033[0;36m
NC = \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Help target
.PHONY: help
help: ## Display this help message
	@echo "$(CYAN)╔═══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(CYAN)║              TALOS PROXMOX GITOPS MAKEFILE                    ║$(NC)"
	@echo "$(CYAN)║           3-Layer Infrastructure Management                   ║$(NC)"
	@echo "$(CYAN)╚═══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Quick Commands:$(NC)"
	@echo "  $(GREEN)make deploy$(NC)              - Full 3-layer deployment"
	@echo "  $(GREEN)make destroy$(NC)             - Destroy all infrastructure"
	@echo "  $(GREEN)make status$(NC)              - Check cluster status"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Deployment Order:$(NC)"
	@echo "  1. $(GREEN)make layer1$(NC)  - Deploy infrastructure (3 Talos + 1 NFS = 4 VMs)"
	@echo "  2. $(GREEN)make layer2$(NC)  - Configure NFS + Talos Kubernetes"
	@echo "  3. $(GREEN)make layer3$(NC)  - Deploy ArgoCD + GitOps apps"
	@echo ""

# ============================================================================
# FULL DEPLOYMENT
# ============================================================================

.PHONY: deploy
deploy: ## Full deployment (all 3 layers)
	@echo "$(GREEN)🚀 Starting full homelab deployment...$(NC)"
	@./deploy-homelab.sh

.PHONY: deploy-skip-layer1
deploy-skip-layer1: ## Deploy layers 2-3 only
	@echo "$(GREEN)🚀 Deploying layers 2-3...$(NC)"
	@./deploy-homelab.sh --skip-layer1

.PHONY: deploy-skip-layer2
deploy-skip-layer2: ## Deploy layers 1 and 3 only
	@echo "$(GREEN)🚀 Deploying layers 1 and 3...$(NC)"
	@./deploy-homelab.sh --skip-layer2

# ============================================================================
# LAYER 1 - INFRASTRUCTURE (Terraform)
# ============================================================================

.PHONY: layer1
layer1: terraform-apply ## Deploy Layer 1 infrastructure

.PHONY: terraform-init
terraform-init: ## Initialize Terraform
	@echo "$(BLUE)🔧 Initializing Terraform...$(NC)"
	cd $(TERRAFORM_DIR) && terraform init

.PHONY: terraform-validate
terraform-validate: ## Validate Terraform configuration
	@echo "$(BLUE)✓ Validating Terraform configuration...$(NC)"
	cd $(TERRAFORM_DIR) && terraform validate

.PHONY: terraform-plan
terraform-plan: terraform-init ## Plan Terraform changes
	@echo "$(BLUE)📋 Planning infrastructure changes...$(NC)"
	cd $(TERRAFORM_DIR) && terraform plan

.PHONY: terraform-apply
terraform-apply: terraform-init terraform-validate ## Apply Terraform configuration
	@echo "$(GREEN)🚀 Deploying infrastructure...$(NC)"
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo "$(GREEN)✅ Layer 1 Complete!$(NC)"
	@echo "$(YELLOW)Waiting for VMs to boot (60 seconds)...$(NC)"
	@sleep 60
	@echo "$(YELLOW)Checking VM connectivity...$(NC)"
	@for ip in 10.20.0.40 10.20.0.41 10.20.0.42 10.20.0.44; do \
		if timeout 300 bash -c "until ping -c 1 $$ip &>/dev/null; do sleep 5; done"; then \
			echo "$(GREEN)✓$(NC) $$ip is reachable"; \
		else \
			echo "$(RED)✗$(NC) $$ip is not reachable"; \
			exit 1; \
		fi \
	done

.PHONY: terraform-destroy
terraform-destroy: ## Destroy Terraform infrastructure
	@echo "$(RED)⚠️  Destroying infrastructure...$(NC)"
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

.PHONY: terraform-output
terraform-output: ## Show Terraform outputs
	@cd $(TERRAFORM_DIR) && terraform output

# ============================================================================
# LAYER 2 - CONFIGURATION (Ansible + Talos)
# ============================================================================

.PHONY: layer2
layer2: ansible-configure ## Deploy Layer 2 configuration

.PHONY: ansible-configure
ansible-configure: ## Run Ansible configuration (NFS + Talos)
	@echo "$(GREEN)🔧 Configuring NFS Server and Talos Cluster...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/layer2-configure.yml
	@echo "$(GREEN)✅ Layer 2 Complete!$(NC)"

.PHONY: ansible-nfs-only
ansible-nfs-only: ## Configure NFS server only
	@echo "$(GREEN)🔧 Configuring NFS Server...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/layer2-configure.yml --tags nfs

.PHONY: ansible-talos-only
ansible-talos-only: ## Configure Talos cluster only
	@echo "$(GREEN)🔧 Configuring Talos Cluster...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/layer2-configure.yml --tags talos

.PHONY: ansible-cleanup
ansible-cleanup: ## Cleanup Talos VMs (on failure)
	@echo "$(RED)🧹 Cleaning up Talos VMs...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/cleanup-talos.yml

# ============================================================================
# LAYER 3 - GITOPS (ArgoCD)
# ============================================================================

.PHONY: layer3
layer3: argocd-deploy ## Deploy Layer 3 GitOps

.PHONY: argocd-install
argocd-install: ## Install ArgoCD
	@echo "$(GREEN)📦 Installing ArgoCD...$(NC)"
	cd $(GITOPS_DIR) && ./argocd_install.sh
	@echo "$(GREEN)✅ ArgoCD installed!$(NC)"

.PHONY: argocd-deploy
argocd-deploy: ## Deploy ArgoCD + apps
	@echo "$(GREEN)🚀 Deploying GitOps applications...$(NC)"
	@if ! kubectl get namespace argocd &>/dev/null; then \
		$(MAKE) argocd-install; \
	fi
	kubectl apply -f $(GITOPS_DIR)/app-of-apps.yaml
	@echo "$(GREEN)✅ Layer 3 Complete!$(NC)"

.PHONY: argocd-password
argocd-password: ## Get ArgoCD admin password
	@echo "$(YELLOW)ArgoCD Admin Password:$(NC)"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo

.PHONY: argocd-port-forward
argocd-port-forward: ## Port forward to ArgoCD UI
	@echo "$(GREEN)🌐 Port forwarding ArgoCD UI to localhost:8080$(NC)"
	@echo "$(YELLOW)Access at: https://localhost:8080$(NC)"
	@echo "$(YELLOW)Username: admin$(NC)"
	@echo "$(YELLOW)Password: Run 'make argocd-password'$(NC)"
	kubectl port-forward svc/argocd-server -n argocd 8080:443

# ============================================================================
# CLUSTER MANAGEMENT
# ============================================================================

.PHONY: status
status: ## Check cluster status
	@echo "$(BLUE)📊 Cluster Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)Nodes:$(NC)"
	@kubectl get nodes -o wide 2>/dev/null || echo "$(RED)Cluster not accessible$(NC)"
	@echo ""
	@echo "$(YELLOW)System Pods:$(NC)"
	@kubectl get pods -n kube-system 2>/dev/null || true
	@echo ""
	@echo "$(YELLOW)ArgoCD Applications:$(NC)"
	@kubectl get applications -n argocd 2>/dev/null || true

.PHONY: status-apps
status-apps: ## Check ArgoCD applications status
	@echo "$(BLUE)📦 ArgoCD Applications:$(NC)"
	@kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || echo "$(RED)ArgoCD not deployed$(NC)"

.PHONY: kubeconfig
kubeconfig: ## Display kubeconfig path
	@echo "$(YELLOW)Kubeconfig location:$(NC)"
	@echo "  $(KUBECONFIG_PATH)"
	@echo ""
	@echo "$(YELLOW)To use kubectl:$(NC)"
	@echo "  export KUBECONFIG=$(KUBECONFIG_PATH)"

.PHONY: set-kubeconfig
set-kubeconfig: ## Export KUBECONFIG environment variable
	@echo "Run this command in your shell:"
	@echo "  export KUBECONFIG=$(KUBECONFIG_PATH)"

# ============================================================================
# TALOS MANAGEMENT
# ============================================================================

.PHONY: talos-dashboard
talos-dashboard: ## View Talos dashboard
	@echo "$(BLUE)📊 Talos Dashboard:$(NC)"
	@TALOSCONFIG=/tmp/talos-homelab-cluster/rendered/talosconfig talosctl dashboard

.PHONY: talos-health
talos-health: ## Check Talos cluster health
	@echo "$(BLUE)🏥 Talos Cluster Health:$(NC)"
	@TALOSCONFIG=/tmp/talos-homelab-cluster/rendered/talosconfig talosctl health

.PHONY: talos-logs
talos-logs: ## View Talos logs
	@echo "$(BLUE)📋 Talos Logs (Control Plane):$(NC)"
	@TALOSCONFIG=/tmp/talos-homelab-cluster/rendered/talosconfig talosctl logs -f

# ============================================================================
# CLEANUP
# ============================================================================

.PHONY: destroy
destroy: ## Destroy all infrastructure
	@echo "$(RED)⚠️  WARNING: This will destroy all infrastructure!$(NC)"
	@read -p "Are you sure? (yes/NO): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(RED)🔥 Destroying infrastructure...$(NC)"
	$(MAKE) terraform-destroy
	@echo "$(GREEN)✅ Infrastructure destroyed$(NC)"

.PHONY: clean
clean: ## Clean temporary files
	@echo "$(YELLOW)🧹 Cleaning temporary files...$(NC)"
	rm -rf /tmp/talos-homelab-cluster
	rm -rf $(TERRAFORM_DIR)/.terraform
	rm -rf $(TERRAFORM_DIR)/tfplan
	rm -rf $(TERRAFORM_DIR)/*.tfstate*
	@echo "$(GREEN)✅ Cleanup complete$(NC)"

# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: ping
ping: ## Ping all VMs
	@echo "$(BLUE)📡 Pinging all VMs...$(NC)"
	@for ip in 10.20.0.40 10.20.0.41 10.20.0.42 10.20.0.44; do \
		if ping -c 1 -W 1 $$ip &>/dev/null; then \
			echo "$(GREEN)✓$(NC) $$ip"; \
		else \
			echo "$(RED)✗$(NC) $$ip"; \
		fi \
	done

.PHONY: ssh-nfs
ssh-nfs: ## SSH to NFS server
	@echo "$(GREEN)🔐 SSH to NFS server (10.20.0.44)...$(NC)"
	@ssh ubuntu@10.20.0.44

.PHONY: logs
logs: ## View all system logs
	@echo "$(BLUE)📋 System Logs:$(NC)"
	@kubectl logs -n kube-system -l k8s-app=cilium --tail=50
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# ============================================================================
# VERSION INFO
# ============================================================================

.PHONY: version
version: ## Display version information
	@echo "$(CYAN)📌 Tool Versions:$(NC)"
	@echo "Terraform: $$(terraform version -json | grep terraform_version || echo 'Not installed')"
	@echo "Ansible: $$(ansible --version | head -1 || echo 'Not installed')"
	@echo "kubectl: $$(kubectl version --client --short 2>/dev/null || echo 'Not installed')"
	@echo "talosctl: $$(talosctl version --short 2>/dev/null || echo 'Not installed')"
	@echo "helm: $$(helm version --short 2>/dev/null || echo 'Not installed')"
