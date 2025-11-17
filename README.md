# Talos Proxmox GitOps

> **Production-Ready Homelab Infrastructure with Single-Click Deployment**

A complete Infrastructure-as-Code solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, and ArgoCD GitOps.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Talos](https://img.shields.io/badge/Talos-Latest-blue.svg)](https://www.talos.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-green.svg)](https://kubernetes.io/)

## 🎯 Overview

This project demonstrates enterprise-grade infrastructure automation, showcasing skills in:

- **Infrastructure as Code** (Terraform)
- **Configuration Management** (Ansible)
- **Kubernetes** (Talos Linux)
- **GitOps** (ArgoCD)
- **CI/CD** (GitHub Actions)
- **Cloud Native Technologies** (Cilium, cert-manager, Prometheus, etc.)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TALOS PROXMOX GITOPS                         │
│                   3-Layer Architecture                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Layer 1         │  Terraform Infrastructure
│  Infrastructure  │  ├─ 3x Talos VMs (1 control-plane + 2 workers)
│                  │  └─ 1x NFS Server VM (Ubuntu 24.04)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible Configuration + Talos Setup
│  Configuration   │  ├─ NFS Server (10.20.0.44:/srv/nfs)
│                  │  ├─ Talos Cluster Bootstrap
│                  │  ├─ Cilium CNI Installation
│                  │  └─ **Cleanup on Failure** ✨
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  GitOps Applications
│  GitOps          │  ├─ ArgoCD
│                  │  ├─ cert-manager
│                  │  ├─ ingress-nginx
│                  │  ├─ MetalLB
│                  │  ├─ PostgreSQL (CloudNativePG)
│                  │  ├─ Prometheus Stack
│                  │  └─ More...
└──────────────────┘
```

## ✨ Features

### Core Infrastructure

- **Talos Linux Kubernetes**: Immutable, secure Kubernetes OS
- **High Availability**: 1 control-plane + 2 worker nodes
- **NFS Storage**: Persistent storage for Kubernetes PVCs
- **Failure Recovery**: Automatic Talos VM cleanup on configuration failure

### GitOps Applications

- **ArgoCD**: Declarative GitOps CD for Kubernetes
- **cert-manager**: Automatic SSL certificate management
- **ingress-nginx**: HTTP/HTTPS ingress controller
- **MetalLB**: Load balancer for bare-metal Kubernetes
- **CloudNativePG**: PostgreSQL operator for HA databases
- **Prometheus Stack**: Complete observability (Prometheus + Grafana + Alertmanager)
- **NFS Provisioner**: Dynamic NFS volume provisioning

### Automation

- **Single-Click Deployment**: Via GitHub Actions or local script
- **3-Layer Architecture**: Clean separation of concerns
- **Idempotent**: Safe to run multiple times
- **Self-Healing**: ArgoCD automatically syncs application state

## 🚀 Quick Start

### Prerequisites

**Required Software:**

- [Terraform](https://www.terraform.io/downloads) >= 1.9.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.15
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/#talosctl) >= 1.7
- [Helm](https://helm.sh/docs/intro/install/) >= 3.12

**Infrastructure:**

- Proxmox VE 8.x server
- Network: 10.20.0.0/24
- Available IPs: 10.20.0.40-44
- 1.8 TB storage available

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/jamilshaikh07/talos-proxmox-gitops.git
   cd talos-proxmox-gitops
   ```

2. **Configure Proxmox credentials**

   ```bash
   # Create .env file (not committed to Git)
   export PROXMOX_API_URL="https://your-proxmox-host:8006/api2/json"
   export PROXMOX_API_TOKEN_ID="terraform@pve!terraform"
   export PROXMOX_API_TOKEN_SECRET="your-secret-token"
   ```

3. **Deploy infrastructure**

   ```bash
   # Option 1: Full deployment via Makefile
   make deploy

   # Option 2: Full deployment via script
   ./deploy-homelab.sh

   # Option 3: Layer-by-layer deployment
   make layer1  # Infrastructure
   make layer2  # Configuration + Talos
   make layer3  # GitOps
   ```

### Deployment Time

- **Layer 1** (Infrastructure): ~5 minutes
- **Layer 2** (Configuration + Talos): ~10 minutes
- **Layer 3** (GitOps): ~5 minutes

**Total: ~20 minutes** for complete deployment

## 📋 Deployment Options

### Option 1: Local Deployment (Recommended)

```bash
# Full deployment
./deploy-homelab.sh

# Or use Makefile
make deploy

# Skip specific layers
./deploy-homelab.sh --skip-layer1  # Skip infrastructure
./deploy-homelab.sh --skip-layer2  # Skip configuration
./deploy-homelab.sh --skip-layer3  # Skip GitOps
```

### Option 2: Makefile

```bash
make help     # Show all available commands
make deploy   # Full deployment
make layer1   # Deploy infrastructure only
make layer2   # Configure NFS + Talos only
make layer3   # Deploy GitOps only
make status   # Check cluster status
make destroy  # Destroy all infrastructure
```

### Option 3: GitHub Actions (Advanced)

**Requirements:**
- Self-hosted GitHub Actions runner on Proxmox
- Runner must have network access to Proxmox API and VMs

**Setup:**

1. Deploy a self-hosted runner VM on Proxmox:
   ```bash
   # Follow GitHub's instructions to set up a self-hosted runner
   # https://docs.github.com/en/actions/hosting-your-own-runners
   ```

2. Configure GitHub secrets:
   - `PROXMOX_API_URL`
   - `PROXMOX_API_TOKEN_ID`
   - `PROXMOX_API_TOKEN_SECRET`
   - `SSH_PRIVATE_KEY`
   - `SSH_PUBLIC_KEY`

3. Trigger workflow:
   ```bash
   git push origin main
   ```

4. Monitor deployment in GitHub Actions tab

**Note:** GitHub Actions deployment requires a self-hosted runner because:
- Cloud runners cannot access private Proxmox infrastructure
- Runner needs direct network access to manage VMs
- Talos/kubectl commands need connectivity to cluster nodes

## 🔧 Configuration

### Network Configuration

| Component | IP Address | Description |
|-----------|------------|-------------|
| Control Plane | 10.20.0.40 | Talos master node |
| Worker 1 | 10.20.0.41 | Talos worker node |
| Worker 2 | 10.20.0.42 | Talos worker node |
| NFS Server | 10.20.0.44 | Ubuntu NFS server |
| MetalLB Pool | 10.20.0.81-99 | Load balancer IP range |

### Storage Configuration

- **NFS Server**: 10.20.0.44:/srv/nfs (600 GB)
- **Storage Class**: `nfs-client` (default)
- **Exports**: `/srv/nfs/{shared,media,backups,config}`

### Talos Configuration

- **Talos Version**: v1.11.5
- **Kubernetes Version**: v1.34.1
- **Cluster Name**: homelab-cluster
- **Cluster Endpoint**: https://10.20.0.40:6443
- **CNI**: Cilium 1.16.5
- **Allow Control Plane Scheduling**: Yes

## 📊 Management

### Access Cluster

```bash
# Export kubeconfig
export KUBECONFIG=talos-homelab-cluster/rendered/kubeconfig

# Check cluster status
kubectl get nodes
kubectl get pods -A

# Or use make commands
make status
```

### Access ArgoCD

```bash
# Get admin password
make argocd-password

# Port forward to ArgoCD UI
make argocd-port-forward
# Or manually:
# kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at: https://localhost:8080
# Username: admin
```

### Talos Management

```bash
# Set Talos config
export TALOSCONFIG=talos-homelab-cluster/rendered/talosconfig

# Check cluster health
make talos-health
# Or manually:
# talosctl health

# View dashboard
make talos-dashboard
# Or manually:
# talosctl dashboard

# View logs
make talos-logs
# Or manually:
# talosctl logs -f
```

## 🛠️ Troubleshooting

### Layer 2 Failure (Talos Setup)

If Talos configuration fails, the deployment will preserve infrastructure for debugging and retry:

```bash
# Retry Layer 2 without destroying VMs
make layer2

# Or destroy only Talos VMs and redeploy (keeps NFS)
make destroy-talos
make layer1
make layer2

# Or destroy everything and start fresh
make destroy
make deploy
```

### Idempotent Operations

All layers are idempotent and safe to re-run:

```bash
# Re-run any layer safely
make layer2  # Will skip if configs already exist
make layer3  # Will skip if ArgoCD already installed
```

### Cluster Access Issues

```bash
# View cluster status
make status

# Export kubeconfig
export KUBECONFIG=talos-homelab-cluster/rendered/kubeconfig

# Check nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A
```

### ArgoCD Application Issues

```bash
# Check application status
make status-apps

# View ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## 📚 Documentation

- **ARCHITECTURE.md** - Detailed architecture documentation
- **GitHub Actions Workflow** - CI/CD pipeline ([.github/workflows/deploy-homelab.yml](.github/workflows/deploy-homelab.yml))
- **Terraform Modules** - Infrastructure code ([terraform/proxmox-homelab/](terraform/proxmox-homelab/))
- **Ansible Roles** - Configuration management ([ansible/roles/](ansible/roles/))
- **GitOps Apps** - ArgoCD applications ([gitops/apps/](gitops/apps/))

## 🧪 Testing

```bash
# Test infrastructure connectivity
make ping

# Verify cluster health
make talos-health

# Check all components
make status
```

## 🗑️ Cleanup

```bash
# Destroy only Talos VMs (preserve NFS)
make destroy-talos

# Destroy all infrastructure (Talos + NFS)
make destroy
```

## 🎯 Makefile Commands

### Deployment
- `make deploy` - Full 3-layer deployment
- `make layer1` - Deploy infrastructure (Terraform)
- `make layer2` - Configure NFS + Talos cluster (Ansible)
- `make layer3` - Deploy GitOps applications (ArgoCD)

### Management
- `make status` - Check cluster status
- `make status-apps` - Check ArgoCD applications
- `make kubeconfig` - Display kubeconfig path
- `make argocd-password` - Get ArgoCD admin password
- `make argocd-port-forward` - Port forward to ArgoCD UI

### Talos
- `make talos-health` - Check Talos cluster health
- `make talos-dashboard` - View Talos dashboard
- `make talos-logs` - View Talos logs

### Cleanup
- `make destroy-talos` - Destroy only Talos VMs
- `make destroy` - Destroy all infrastructure

### Help
- `make help` - Show all available commands

## 🔐 Security

- Talos secrets are **not committed** to Git (see [.gitignore](.gitignore))
- Use environment variables for Proxmox credentials
- ArgoCD credentials stored in Kubernetes secrets
- SSH keys managed via GitHub Secrets (for GitHub Actions)

## 🤝 Contributing

This is a personal showcase project, but feedback and suggestions are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

- **Friend's Homelab**: Inspired by production-ready configurations from [homelab-gitops](https://github.com/hikmahtech/homelab-gitops)
- **Talos Linux**: For the amazing immutable Kubernetes OS
- **ArgoCD**: For declarative GitOps made easy

## 📧 Contact

For inquiries about this project or professional opportunities:

- GitHub: [@jamilshaikh07](https://github.com/jamilshaikh07)
- Project Link: [https://github.com/jamilshaikh07/talos-proxmox-gitops](https://github.com/jamilshaikh07/talos-proxmox-gitops)

---

**Built with ❤️ for showcasing infrastructure automation skills**

🎯 **Goal**: Demonstrate production-ready infrastructure automation worth $100k+ compensation
