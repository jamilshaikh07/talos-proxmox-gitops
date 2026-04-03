# Talos Proxmox GitOps Makefile - 3-Layer Infrastructure Management
# ====================================================================

# Configuration
TERRAFORM_DIR = terraform/proxmox-homelab
ANSIBLE_DIR = ansible
GITOPS_DIR = gitops
TALOS_CONFIG_DIR = talos-homelab-cluster
KUBECONFIG_PATH = $(TALOS_CONFIG_DIR)/rendered/kubeconfig

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
	@echo "  $(GREEN)make create-templates$(NC)         - Create cloud-init templates (Debian + Ubuntu)"
	@echo "  $(GREEN)make deploy$(NC)                   - Full 3-layer deployment"
	@echo "  $(GREEN)make setup-homelab-access$(NC)     - Configure DNS + trust CA certificate"
	@echo "  $(GREEN)make status$(NC)                   - Check cluster status"
	@echo "  $(GREEN)make destroy$(NC)                  - Destroy all infrastructure"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Deployment Order:$(NC)"
	@echo "  0. $(GREEN)make create-templates$(NC)  - Create cloud-init templates (run once)"
	@echo "  1. $(GREEN)make layer1$(NC)  - Deploy Talos VMs (CP + workers)"
	@echo "  2. $(GREEN)make layer2$(NC)  - Configure Talos Kubernetes cluster"
	@echo "  3. $(GREEN)make layer3$(NC)   - Deploy ArgoCD + GitOps apps"
	@echo ""
	@echo ""

# ============================================================================
# LAYER 0 - TEMPLATES
# ============================================================================

.PHONY: create-templates
create-templates: ## Create both Debian 12 and Ubuntu 24.04 cloud-init templates
	@echo "$(GREEN)🏗️  Creating cloud-init templates...$(NC)"
	@./create-cloud-templates.sh

.PHONY: create-debian
create-debian: ## Create only Debian 12 cloud-init template
	@echo "$(GREEN)🏗️  Creating Debian 12 template...$(NC)"
	@DEBIAN_ONLY=true ./create-cloud-templates.sh

.PHONY: create-ubuntu
create-ubuntu: ## Create only Ubuntu 24.04 cloud-init template
	@echo "$(GREEN)🏗️  Creating Ubuntu 24.04 template...$(NC)"
	@UBUNTU_ONLY=true ./create-cloud-templates.sh

# ============================================================================
# FULL DEPLOYMENT
# ============================================================================

.PHONY: deploy
deploy: ## Full deployment (all 3 layers) + automatic homelab access setup
	@echo "$(GREEN)🚀 Starting full homelab deployment...$(NC)"
	@./deploy-homelab.sh
	@echo ""
	@echo "$(YELLOW)⏳ Waiting for cluster to be ready (60 seconds)...$(NC)"
	@sleep 60
	@echo "$(GREEN)🎯 Setting up homelab access (DNS + CA trust)...$(NC)"
	@$(MAKE) setup-homelab-access

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
	@echo "$(YELLOW)Checking Talos VM connectivity (via Proxmox host)...$(NC)"
	@for ip in 192.168.60.40 192.168.60.41; do \
		if timeout 300 bash -c "until ssh prox 'ping -c 1 $$ip' &>/dev/null; do sleep 5; done"; then \
			echo "$(GREEN)✓$(NC) $$ip is reachable"; \
		else \
			echo "$(RED)✗$(NC) $$ip is not reachable"; \
			exit 1; \
		fi \
	done

.PHONY: terraform-destroy
terraform-destroy: ## Destroy Terraform infrastructure (use 'make destroy' for safety)
	@echo "$(RED)⚠️  Destroying infrastructure (no confirmation)...$(NC)"
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

.PHONY: terraform-output
terraform-output: ## Show Terraform outputs
	@cd $(TERRAFORM_DIR) && terraform output

.PHONY: sync-inventory
sync-inventory: ## Generate Ansible inventory from Terraform outputs
	@echo "$(BLUE)🔄 Syncing inventory from Terraform...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform output -json > ../../ansible/terraform-inventory.json
	@python3 scripts/generate-ansible-inventory.py
	@echo "$(GREEN)✅ Ansible inventory synced from Terraform$(NC)"

# ============================================================================
# LAYER 2 - CONFIGURATION (Ansible + Talos)
# ============================================================================

.PHONY: layer2
layer2: ansible-configure ## Deploy Layer 2 configuration

.PHONY: ansible-configure
ansible-configure: ## Run Ansible configuration (Talos cluster)
	@echo "$(GREEN)🔧 Configuring Talos Kubernetes Cluster...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/layer2-configure.yml --tags talos
	@echo "$(GREEN)✅ Layer 2 Complete!$(NC)"

.PHONY: ansible-talos-only
ansible-talos-only: ## Configure Talos cluster only
	@echo "$(GREEN)🔧 Configuring Talos Cluster...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/layer2-configure.yml --tags talos

.PHONY: ansible-cleanup
ansible-cleanup: ## Cleanup Talos VMs (on failure)
	@echo "$(RED)🧹 Cleaning up Talos VMs...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/cleanup-talos.yml

.PHONY: regenerate-worker-configs
regenerate-worker-configs: ## Regenerate missing worker configs (run after adding new workers)
	@echo "$(YELLOW)🔄 Regenerating missing worker configurations...$(NC)"
	@echo "$(BLUE)This will generate configs only for workers that don't have one yet$(NC)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.yml playbooks/layer2-configure.yml --tags talos
	@echo "$(GREEN)✅ Worker configs updated$(NC)"
	@echo "$(BLUE)Configs location: $(TALOS_CONFIG_DIR)/rendered/$(NC)"
	@ls -lh $(TALOS_CONFIG_DIR)/rendered/talos-wk-*.yaml 2>/dev/null || echo "$(YELLOW)No worker configs found yet$(NC)"

# ============================================================================
# LAYER 3 - GITOPS (ArgoCD)
# ============================================================================

.PHONY: layer3
layer3: ansible-gitops ## Deploy Layer 3 GitOps

.PHONY: ansible-gitops
ansible-gitops: ## Deploy ArgoCD + app-of-apps using Ansible
	@echo "$(GREEN)🚀 Deploying GitOps (ArgoCD + Applications)...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/layer3-gitops.yml
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

.PHONY: label-nodes
label-nodes: ## Label Kubernetes nodes with roles and topology
	@echo "$(BLUE)🏷️  Labeling Kubernetes nodes...$(NC)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/hosts.yml playbooks/talos-cluster.yml --tags labels
	@echo "$(GREEN)✅ Nodes labeled$(NC)"
	@kubectl get nodes --show-labels

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
destroy: ## Destroy all Talos VMs
	@echo "$(RED)⚠️  WARNING: This will destroy all Talos VMs!$(NC)"
	@echo "$(YELLOW)The following will be destroyed:$(NC)"
	@echo "  - Talos control-plane + worker VMs"
	@echo "$(GREEN)The following will NOT be affected:$(NC)"
	@echo "  - External OMV NFS server (192.168.60.229)"
	@echo ""
	@read -p "Type 'yes' to confirm destruction: " confirm && [ "$$confirm" = "yes" ] || { echo "$(GREEN)Destroy cancelled.$(NC)"; exit 1; }
	@echo "$(RED)🔥 Destroying infrastructure...$(NC)"
	cd $(TERRAFORM_DIR) && terraform init && terraform destroy -auto-approve
	@echo "$(BLUE)🧹 Cleaning up SSH known_hosts...$(NC)"
	@ssh-keygen -f "$$HOME/.ssh/known_hosts" -R "192.168.60.40" 2>/dev/null || true
	@echo "$(GREEN)✅ Infrastructure destroyed and SSH keys cleaned$(NC)"

.PHONY: destroy-all
destroy-all: ## Destroy all VMs AND remove Talos config directory
	@echo "$(RED)⚠️  WARNING: This will destroy EVERYTHING!$(NC)"
	@echo "$(YELLOW)The following will be destroyed:$(NC)"
	@echo "  - All Talos VMs"
	@echo "  - Talos configuration directory: $(TALOS_CONFIG_DIR)"
	@echo "  - All kubeconfigs and secrets"
	@echo "  - SSH known_hosts entries"
	@echo ""
	@read -p "Type 'yes' to confirm complete destruction: " confirm && [ "$$confirm" = "yes" ] || { echo "$(GREEN)Destroy cancelled.$(NC)"; exit 1; }
	@echo "$(RED)🔥 Destroying infrastructure...$(NC)"
	cd $(TERRAFORM_DIR) && terraform init && terraform destroy -auto-approve
	@echo "$(RED)🗑️  Removing Talos configuration directory...$(NC)"
	@sudo rm -rf $(TALOS_CONFIG_DIR)
	@echo "$(BLUE)🧹 Cleaning up SSH known_hosts...$(NC)"
	@ssh-keygen -f "$$HOME/.ssh/known_hosts" -R "192.168.60.40" 2>/dev/null || true
	@echo "$(GREEN)✅ Everything destroyed and cleaned up$(NC)"

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
ping: ## Ping Talos VMs + NFS server
	@echo "$(BLUE)📡 Pinging Talos VMs...$(NC)"
	@for ip in 192.168.60.40 192.168.60.41; do \
                if ping -c 1 -W 1 $$ip &>/dev/null; then \
                        echo "$(GREEN)✓$(NC) $$ip (Talos)"; \
                else \
                        echo "$(RED)✗$(NC) $$ip (Talos)"; \
                fi \
        done

.PHONY: logs
logs: ## View all system logs
	@echo "$(BLUE)📋 System Logs:$(NC)"
	@kubectl logs -n kube-system -l k8s-app=cilium --tail=50
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# ============================================================================
# DNS & CERTIFICATE MANAGEMENT
# ============================================================================

.PHONY: setup-dns
setup-dns: ## Add *.lab.jamilshaikh.in domains to /etc/hosts
	@echo "$(YELLOW)📝 Adding *.lab.jamilshaikh.in domains to /etc/hosts...$(NC)"
	@if grep -q "argocd.lab.jamilshaikh.in" /etc/hosts 2>/dev/null; then \
		echo "$(GREEN)✓$(NC) Domains already configured in /etc/hosts"; \
	else \
		echo "$(YELLOW)Adding homelab domains...$(NC)"; \
		echo "" | sudo tee -a /etc/hosts; \
		echo "# Homelab Services (*.lab.jamilshaikh.in)" | sudo tee -a /etc/hosts; \
		echo "192.168.60.81 argocd.lab.jamilshaikh.in grafana.lab.jamilshaikh.in prometheus.lab.jamilshaikh.in traefik.lab.jamilshaikh.in uptime.lab.jamilshaikh.in homarr.lab.jamilshaikh.in" | sudo tee -a /etc/hosts; \
		echo "$(GREEN)✅ DNS configuration added to /etc/hosts$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)🌐 Access your services:$(NC)"
	@echo "  https://argocd.lab.jamilshaikh.in       - ArgoCD UI"
	@echo "  https://grafana.lab.jamilshaikh.in      - Grafana dashboards"
	@echo "  https://prometheus.lab.jamilshaikh.in   - Prometheus UI"
	@echo "  https://traefik.lab.jamilshaikh.in      - Traefik dashboard"
	@echo "  https://uptime.lab.jamilshaikh.in       - Uptime Kuma monitoring"
	@echo "  https://homarr.lab.jamilshaikh.in       - Homarr dashboard"

.PHONY: remove-dns
remove-dns: ## Remove *.lab.jamilshaikh.in domains from /etc/hosts
	@echo "$(YELLOW)🗑️  Removing *.lab.jamilshaikh.in domains from /etc/hosts...$(NC)"
	@sudo sed -i '/# Homelab Services/,+1d' /etc/hosts 2>/dev/null || true
	@echo "$(GREEN)✅ DNS configuration removed$(NC)"

.PHONY: extract-ca
extract-ca: ## Extract homelab CA certificate
	@echo "$(BLUE)📜 Extracting homelab CA certificate...$(NC)"
	@kubectl get secret homelab-root-ca-secret -n cert-manager \
		-o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > homelab-ca.crt
	@if [ -f homelab-ca.crt ]; then \
		echo "$(GREEN)✅ CA certificate extracted to homelab-ca.crt$(NC)"; \
		echo "$(YELLOW)Certificate details:$(NC)"; \
		openssl x509 -in homelab-ca.crt -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After)" || true; \
	else \
		echo "$(RED)❌ Failed to extract CA certificate$(NC)"; \
		echo "$(YELLOW)Make sure cert-manager is deployed and homelab-root-ca-secret exists$(NC)"; \
		exit 1; \
	fi

.PHONY: trust-ca
trust-ca: extract-ca ## Trust homelab CA certificate (Linux)
	@echo "$(YELLOW)🔐 Installing homelab CA certificate...$(NC)"
	@if [ "$$(uname)" = "Linux" ]; then \
		echo "$(YELLOW)Removing old certificate if exists...$(NC)"; \
		sudo rm -f /usr/local/share/ca-certificates/homelab-ca.crt; \
		echo "$(YELLOW)Installing fresh certificate...$(NC)"; \
		sudo cp homelab-ca.crt /usr/local/share/ca-certificates/homelab-ca.crt; \
		sudo update-ca-certificates --fresh; \
		echo "$(GREEN)✅ CA certificate installed and trusted (Linux)$(NC)"; \
	elif [ "$$(uname)" = "Darwin" ]; then \
		sudo security delete-certificate -c "Homelab Root CA" /Library/Keychains/System.keychain 2>/dev/null || true; \
		sudo security add-trusted-cert -d -r trustRoot \
			-k /Library/Keychains/System.keychain homelab-ca.crt; \
		echo "$(GREEN)✅ CA certificate installed and trusted (macOS)$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  Unsupported OS. Please install homelab-ca.crt manually.$(NC)"; \
		echo "For Windows: certutil -addstore -f \"ROOT\" homelab-ca.crt"; \
	fi
	@echo ""
	@echo "$(BLUE)🌐 You can now access services with valid HTTPS:$(NC)"
	@echo "  https://argocd.lab.jamilshaikh.in"
	@echo "  https://grafana.lab.jamilshaikh.in"
	@echo "  https://prometheus.lab.jamilshaikh.in"
	@echo "  https://traefik.lab.jamilshaikh.in"
	@echo "  https://uptime.lab.jamilshaikh.in"
	@echo "  https://homarr.lab.jamilshaikh.in"

.PHONY: untrust-ca
untrust-ca: ## Remove homelab CA certificate
	@echo "$(YELLOW)🗑️  Removing homelab CA certificate...$(NC)"
	@if [ "$$(uname)" = "Linux" ]; then \
		sudo rm -f /usr/local/share/ca-certificates/homelab-ca.crt; \
		sudo update-ca-certificates --fresh; \
		echo "$(GREEN)✅ CA certificate removed (Linux)$(NC)"; \
	elif [ "$$(uname)" = "Darwin" ]; then \
		sudo security delete-certificate -c "Homelab Root CA" \
			/Library/Keychains/System.keychain 2>/dev/null || true; \
		echo "$(GREEN)✅ CA certificate removed (macOS)$(NC)"; \
	fi
	@rm -f homelab-ca.crt

.PHONY: setup-homelab-access
setup-homelab-access: setup-dns trust-ca ## Complete setup: DNS + CA trust
	@echo ""
	@echo "$(GREEN)╔═══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║          HOMELAB ACCESS SETUP COMPLETE!                       ║$(NC)"
	@echo "$(GREEN)╚═══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)🎉 You can now access all services via HTTPS with valid certificates!$(NC)"
	@echo ""
	@echo "$(CYAN)Next steps:$(NC)"
	@echo "  1. Open your browser to: $(GREEN)https://argocd.lab$(NC)"
	@echo "  2. Get ArgoCD password: $(GREEN)make argocd-password$(NC)"
	@echo "  3. Check cluster status: $(GREEN)make status$(NC)"

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
