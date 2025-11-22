# Talos Proxmox GitOps

> **Production-Ready Homelab Infrastructure with Single-Click Deployment**

A complete Infrastructure-as-Code solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, and ArgoCD GitOps with Longhorn distributed storage.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Talos](https://img.shields.io/badge/Talos-v1.11.5-blue.svg)](https://www.talos.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.1-green.svg)](https://kubernetes.io/)
[![Longhorn](https://img.shields.io/badge/Longhorn-v1.10.1-orange.svg)](https://longhorn.io/)

## 🎯 Overview

This project demonstrates enterprise-grade infrastructure automation, showcasing skills in:

- **Infrastructure as Code** (Terraform)
- **Configuration Management** (Ansible)
- **Kubernetes** (Talos Linux v1.11.5 with Kubernetes v1.34.1)
- **GitOps** (ArgoCD with Helm)
- **Distributed Storage** (Longhorn v1.10.1)
- **CI/CD** (GitHub Actions)
- **Cloud Native Technologies** (Cilium, cert-manager, Prometheus, etc.)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TALOS PROXMOX GITOPS                         │
│                   4-Layer Architecture                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Layer 0         │  Cloud-Init Templates (Run Once)
│  Templates       │  ├─ Debian 12 Bookworm template (ID: 9002)
│                  │  └─ Ubuntu 24.04 LTS template (ID: 9003)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 1         │  Terraform Infrastructure
│  Infrastructure  │  ├─ 3x Talos VMs (1 control-plane + 2 workers)
│                  │  │   └─ 50GB OS + 500GB Longhorn disk each
│                  │  └─ 1x NFS Server VM (Ubuntu 24.04 - 600GB)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible Configuration + Talos Setup
│  Configuration   │  ├─ NFS Server (10.20.0.44:/srv/nfs)
│                  │  ├─ Talos Cluster Bootstrap (v1.11.5)
│                  │  ├─ Longhorn Support Configuration
│                  │  ├─ Cilium CNI Installation (v1.16.5)
│                  │  └─ Metrics Server + Cert Rotation
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  GitOps Applications (via ArgoCD Helm)
│  GitOps          │  ├─ ArgoCD (Helm v7.7.12)
│                  │  ├─ Longhorn (PRIMARY storage - 1.5TB)
│                  │  ├─ NFS Provisioner (SECONDARY storage)
│                  │  ├─ Metrics Server (Talos-compatible)
│                  │  ├─ cert-manager
│                  │  ├─ ingress-nginx
│                  │  ├─ MetalLB
│                  │  ├─ PostgreSQL (CloudNativePG)
│                  │  ├─ Prometheus Stack (with Longhorn dashboard)
│                  │  └─ More...
└──────────────────┘
```

## ✨ Features

### Core Infrastructure

- **Talos Linux Kubernetes**: Immutable, secure Kubernetes OS (v1.11.5)
- **Kubernetes v1.34.1**: Latest stable release
- **High Availability**: 1 control-plane + 2 worker nodes (3-node cluster)
- **Longhorn Distributed Storage**: 1.5TB replicated block storage (PRIMARY)
  - 3x 500GB disks across all nodes
  - 2-replica configuration for HA
  - NFS backup target integration
- **NFS Storage**: 600GB centralized storage (SECONDARY) for backups and media
- **Failure Recovery**: Automatic Talos VM cleanup on configuration failure

### GitOps Applications

- **ArgoCD**: Declarative GitOps CD for Kubernetes (Helm-based deployment)
- **Longhorn v1.10.1**: Cloud-native distributed block storage
  - Default storage class
  - Prometheus ServiceMonitor enabled
  - Grafana dashboard included
- **Metrics Server**: Kubernetes resource metrics (Talos-compatible)
- **cert-manager**: Automatic SSL certificate management
- **ingress-nginx**: HTTP/HTTPS ingress controller
- **MetalLB**: Load balancer for bare-metal Kubernetes
- **CloudNativePG**: PostgreSQL operator for HA databases
- **Prometheus Stack**: Complete observability (Prometheus + Grafana + Alertmanager)
- **NFS Provisioner**: Dynamic NFS volume provisioning (secondary storage)
- **Cilium v1.16.5**: eBPF-based CNI with Gateway API support

### Automation

- **Single-Click Deployment**: Via Makefile or local script
- **4-Layer Architecture**: Clean separation of concerns
- **Idempotent**: Safe to run multiple times
- **Self-Healing**: ArgoCD automatically syncs application state
- **Template Creation**: Automated Debian 12 and Ubuntu 24.04 cloud-init templates

## 🚀 Quick Start

### Prerequisites

**Required Software:**

- [Terraform](https://www.terraform.io/downloads) >= 1.9.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.15
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/#talosctl) >= 1.11
- [Helm](https://helm.sh/docs/intro/install/) >= 3.12

**Infrastructure:**

- Proxmox VE 8.x server
- Network: 10.20.0.0/24
- Available IPs: 10.20.0.40-44
- Storage: 1.8TB available (1.5TB for Longhorn + 600GB for NFS)

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

3. **Create cloud-init templates (one-time setup)**

   ```bash
   make create-templates
   # Creates Debian 12 (ID: 9002) and Ubuntu 24.04 (ID: 9003) templates
   ```

4. **Deploy infrastructure**

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

- **Layer 0** (Templates): ~10 minutes (one-time setup)
- **Layer 1** (Infrastructure): ~5 minutes
- **Layer 2** (Configuration + Talos): ~10 minutes
- **Layer 3** (GitOps): ~5 minutes

**Total: ~30 minutes** for complete deployment (including template creation)

## 📋 Deployment Options

### Option 1: Local Deployment (Recommended)

```bash
# Create templates first (one-time)
make create-templates

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
make help              # Show all available commands
make create-templates  # Create cloud-init templates (Debian + Ubuntu)
make create-debian     # Create only Debian 12 template
make create-ubuntu     # Create only Ubuntu 24.04 template
make deploy            # Full deployment
make layer1            # Deploy infrastructure only
make layer2            # Configure NFS + Talos only
make layer3            # Deploy GitOps only
make status            # Check cluster status
make destroy           # Destroy all infrastructure
```

### Option 3: GitHub Actions (Advanced)

**Requirements:**
- Self-hosted GitHub Actions runner on Proxmox
- Runner must have network access to Proxmox API and VMs

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

#### Longhorn (PRIMARY - Distributed Block Storage)
- **Type**: Distributed replicated block storage
- **Total Capacity**: 1.5TB (3x 500GB disks)
- **Replica Count**: 2 (HA configuration)
- **Storage Class**: `longhorn` (default)
- **Reclaim Policy**: Retain
- **Backup Target**: NFS at 10.20.0.44:/srv/nfs/backups
- **Features**:
  - High performance SSD-backed storage
  - Automatic replication across nodes
  - Snapshot and backup support
  - Prometheus metrics + Grafana dashboard

#### NFS (SECONDARY - Centralized Storage)
- **Server**: 10.20.0.44:/srv/nfs (600GB)
- **Storage Class**: `nfs-client` (non-default)
- **Exports**: `/srv/nfs/{shared,media,backups,config}`
- **Use Cases**: Backups, media files, Longhorn backup target

### Talos Configuration

- **Talos Version**: v1.11.5
- **Kubernetes Version**: v1.34.1
- **Cluster Name**: homelab-cluster
- **Cluster Endpoint**: https://10.20.0.40:6443
- **CNI**: Cilium v1.16.5 (with Gateway API support)
- **Allow Control Plane Scheduling**: Yes
- **Metrics Server**: Enabled (with kubelet cert rotation)
- **Longhorn Support**: Enabled (extraMounts configured)

### Template Configuration

| Template | VM ID | OS | User | Password | SSH Key |
|----------|-------|----|----|----------|---------|
| debian12-template | 9002 | Debian 12 Bookworm | ubuntu | as | Yes |
| ubuntu24-template | 9003 | Ubuntu 24.04 LTS | ubuntu | as | Yes |

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

### Access Longhorn UI

```bash
# Port forward to Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8090:80

# Access at: http://localhost:8090
# View volumes, nodes, disks, and backups
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

### Longhorn Issues

```bash
# Check Longhorn pods
kubectl get pods -n longhorn-system

# Check Longhorn nodes and disks
kubectl get nodes.longhorn.io -n longhorn-system
kubectl get disks.longhorn.io -n longhorn-system

# View Longhorn logs
kubectl logs -n longhorn-system -l app=longhorn-manager

# Access Longhorn UI for troubleshooting
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8090:80
```

### Storage Issues

```bash
# Check storage classes
kubectl get storageclass

# Longhorn should be default:
# NAME           PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE
# longhorn (default)  driver.longhorn.io   Retain          Immediate
# nfs-client          cluster.local/nfs-client  Delete    Immediate

# Test Longhorn PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-longhorn-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-longhorn-pvc
kubectl get pv
```

### Idempotent Operations

All layers are idempotent and safe to re-run:

```bash
# Re-run any layer safely
make layer2  # Will skip if configs already exist
make layer3  # Will skip if ArgoCD already installed
```

## 🎯 Makefile Commands

### Layer 0 - Templates
- `make create-templates` - Create both Debian 12 and Ubuntu 24.04 templates
- `make create-debian` - Create only Debian 12 template
- `make create-ubuntu` - Create only Ubuntu 24.04 template

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
- `make destroy-talos` - Destroy only Talos VMs (preserve NFS)
- `make destroy` - Destroy all infrastructure (with confirmation)
- `make clean` - Clean temporary files

### Utilities
- `make help` - Show all available commands
- `make ping` - Ping all VMs
- `make version` - Display tool versions

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

# Test Longhorn storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-pvc
```

## 🗑️ Cleanup

```bash
# Destroy only Talos VMs (preserve NFS)
make destroy-talos

# Destroy all infrastructure (Talos + NFS)
make destroy
```

## 🔐 Security

- Talos secrets are **not committed** to Git (see [.gitignore](.gitignore))
- Use environment variables for Proxmox credentials
- ArgoCD credentials stored in Kubernetes secrets
- SSH keys managed via GitHub Secrets (for GitHub Actions)
- Longhorn encryption support ready (can be enabled via Helm values)

## 📈 Monitoring

### Grafana Dashboards
- **Longhorn Dashboard**: Pre-configured for storage monitoring
- **Prometheus Stack**: Complete observability
- **Node Metrics**: Via metrics-server
- **Application Metrics**: Via ServiceMonitors

Access Grafana:
```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Access at: http://localhost:3000
```

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
- **Longhorn**: For cloud-native distributed block storage

## 📧 Contact

For inquiries about this project or professional opportunities:

- GitHub: [@jamilshaikh07](https://github.com/jamilshaikh07)
- Project Link: [https://github.com/jamilshaikh07/talos-proxmox-gitops](https://github.com/jamilshaikh07/talos-proxmox-gitops)

---

**Built with ❤️ for showcasing DevOps/SRE skills**
