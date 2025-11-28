# Talos Proxmox GitOps

> **Production-Ready Homelab Infrastructure with Single-Click Deployment**

A complete Infrastructure-as-Code solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, and ArgoCD GitOps with Longhorn distributed storage.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Talos](https://img.shields.io/badge/Talos-v1.11.5-blue.svg)](https://www.talos.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.1-green.svg)](https://kubernetes.io/)
[![Longhorn](https://img.shields.io/badge/Longhorn-v1.10.1-orange.svg)](https://longhorn.io/)

## Overview

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
│                   3-Layer Architecture                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Layer 0         │  Cloud-Init Templates (Run Once)
│  Templates       │  ├─ Debian 12 Bookworm template (ID: 9002)
│                  │  └─ Ubuntu 24.04 LTS template (ID: 9003)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 1         │  Terraform Infrastructure
│  Infrastructure  │  ├─ 1x Talos Control Plane VM (50GB OS + 500GB Longhorn)
│                  │  ├─ 3x Talos Worker VMs (50GB OS + 500GB Longhorn each)
│                  │  └─ 1x Bare Metal Worker (optional)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible Configuration + Talos Setup
│  Configuration   │  ├─ Talos Cluster Bootstrap (v1.11.5)
│                  │  ├─ Longhorn Disk Configuration (/dev/sdb)
│                  │  ├─ Cilium CNI Installation (v1.16.5)
│                  │  └─ Metrics Server + Cert Rotation
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  GitOps Applications (via ArgoCD Helm)
│  GitOps          │  ├─ ArgoCD (Helm v7.7.12)
│                  │  ├─ Longhorn (PRIMARY storage - 2TB+)
│                  │  ├─ NFS Provisioner (SECONDARY - External OMV)
│                  │  ├─ Metrics Server (Talos-compatible)
│                  │  ├─ cert-manager + trust-manager
│                  │  ├─ Traefik Ingress Controller
│                  │  ├─ MetalLB Load Balancer
│                  │  ├─ PostgreSQL (Crunchy Postgres Operator)
│                  │  ├─ Prometheus Stack (Grafana + Alertmanager)
│                  │  ├─ Loki + Promtail (Log Aggregation)
│                  │  ├─ Tempo (Distributed Tracing)
│                  │  └─ More...
└──────────────────┘
```

## Features

### Core Infrastructure

- **Talos Linux Kubernetes**: Immutable, secure Kubernetes OS (v1.11.5)
- **Kubernetes v1.34.1**: Latest stable release
- **Hybrid Cluster**: VM workers + optional bare metal workers
- **Longhorn Distributed Storage**: 2TB+ replicated block storage (PRIMARY)
  - Dedicated /dev/sdb disks on all nodes (500GB each)
  - 2-replica configuration for HA
  - NFS backup target integration (external OMV server)
- **External NFS Storage**: OMV server at 10.20.0.229 (SECONDARY)
- **Failure Recovery**: Automatic Talos VM cleanup on configuration failure

### GitOps Applications

- **ArgoCD**: Declarative GitOps CD for Kubernetes (Helm-based deployment)
- **Longhorn v1.10.1**: Cloud-native distributed block storage
  - Default storage class
  - Prometheus ServiceMonitor enabled
  - Grafana dashboard included
- **Metrics Server**: Kubernetes resource metrics (Talos-compatible)
- **cert-manager**: Automatic SSL certificate management
- **Traefik**: Modern HTTP/HTTPS ingress controller with TCP support
- **MetalLB**: Load balancer for bare-metal Kubernetes
- **Crunchy PostgreSQL**: Enterprise PostgreSQL operator for HA databases
- **Prometheus Stack**: Complete observability (Prometheus + Grafana + Alertmanager)
- **Loki + Promtail**: Log aggregation with MinIO S3 backend
- **Tempo**: Distributed tracing
- **NFS Provisioner**: Dynamic NFS volume provisioning (external OMV server)
- **Cilium v1.16.5**: eBPF-based CNI
- **CoreDNS k8s-gateway**: Internal DNS for *.lab.jamilshaikh.in

### Automation

- **Single-Click Deployment**: Via Makefile or local script
- **3-Layer Architecture**: Clean separation of concerns
- **Idempotent**: Safe to run multiple times
- **Self-Healing**: ArgoCD automatically syncs application state
- **Template Creation**: Automated Debian 12 and Ubuntu 24.04 cloud-init templates
- **Bare Metal Auto-Detection**: Auto-detect disks on bare metal nodes via talosctl

## Quick Start

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
- Available IPs: 10.20.0.40-45 (Talos nodes)
- External NFS: OMV server at 10.20.0.229 (optional)
- Storage: 2TB+ for Longhorn (500GB per node)

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

## Configuration

### Network Configuration

| Component | IP Address | Description |
|-----------|------------|-------------|
| Control Plane | 10.20.0.40 | Talos master node |
| Worker 1 | 10.20.0.41 | Talos worker node (VM) |
| Worker 2 | 10.20.0.42 | Talos worker node (VM) |
| Worker 3 | 10.20.0.43 | Talos worker node (VM) |
| Worker 4 | 10.20.0.45 | Talos worker node (Bare Metal - optional) |
| OMV NFS Server | 10.20.0.229 | External OpenMediaVault NFS |
| MetalLB Pool | 10.20.0.81-99 | Load balancer IP range |
| Traefik LB | 10.20.0.81 | Ingress controller |
| k8s-gateway DNS | 10.20.0.82 | Internal DNS server |

### Storage Configuration

#### Longhorn (PRIMARY - Distributed Block Storage)
- **Type**: Distributed replicated block storage
- **Total Capacity**: 2TB+ (500GB per node x 4-5 nodes)
- **Disk Path**: `/var/mnt/longhorn` (mounted from `/dev/sdb`)
- **Replica Count**: 2 (HA configuration)
- **Storage Class**: `longhorn` (default)
- **Reclaim Policy**: Retain
- **Backup Target**: `nfs://10.20.0.229:/export/k8s-nfs/longhorn-backups`
- **Features**:
  - High performance SSD-backed storage
  - Automatic replication across nodes
  - Snapshot and backup support
  - Prometheus metrics + Grafana dashboard

#### NFS (SECONDARY - External OMV Storage)
- **Server**: 10.20.0.229:/export/k8s-nfs (External OMV)
- **Storage Class**: `nfs-client` (non-default)
- **Use Cases**: Backups, media files, Longhorn backup target, logs

### Node Disk Configuration

| Node | Install Disk | Longhorn Disk | Longhorn Size |
|------|--------------|---------------|---------------|
| talos-cp-01 (VM) | /dev/sda | /dev/sdb | 500GB |
| talos-wk-01 (VM) | /dev/sda | /dev/sdb | 500GB |
| talos-wk-02 (VM) | /dev/sda | /dev/sdb | 500GB |
| talos-wk-03 (VM) | /dev/sda | /dev/sdb | 500GB |
| talos-wk-04 (Bare Metal) | /dev/nvme0n1 | /dev/sda | 512GB |

### Adding Bare Metal Workers

The inventory script supports auto-detection of disks on bare metal nodes:

```bash
# Auto-detect disks on a new bare metal node
./scripts/generate-ansible-inventory.py --baremetal-ip 10.20.0.45

# Auto-detect disks on existing bare metal nodes in config
./scripts/generate-ansible-inventory.py --detect-baremetal-disks

# Specify custom hostname
./scripts/generate-ansible-inventory.py --baremetal-ip 10.20.0.45 --baremetal-hostname talos-wk-05
```

**Disk Detection Logic:**
- Install disk: Prefers NVMe (smallest), falls back to smallest non-USB disk
- Longhorn disk: Prefers largest SATA/SAS disk, falls back to largest NVMe

### Talos Configuration

- **Talos Version**: v1.11.5
- **Kubernetes Version**: v1.34.1
- **Cluster Name**: homelab-cluster
- **Cluster Endpoint**: https://10.20.0.40:6443
- **CNI**: Cilium v1.16.5
- **Allow Control Plane Scheduling**: Yes
- **Metrics Server**: Enabled (with kubelet cert rotation)
- **Longhorn Support**: Enabled (extraMounts configured)

## Management

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

# Access at: https://localhost:8080
# Username: admin
```

### Access Longhorn UI

```bash
# Port forward to Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8090:80

# Access at: http://localhost:8090
```

### Access Services via Ingress

With DNS configured (k8s-gateway at 10.20.0.82):

| Service | URL |
|---------|-----|
| Grafana | https://grafana.lab.jamilshaikh.in |
| ArgoCD | https://argocd.lab.jamilshaikh.in |
| Longhorn | https://longhorn.lab.jamilshaikh.in |
| Prometheus | https://prometheus.lab.jamilshaikh.in |
| Traefik | https://traefik.lab.jamilshaikh.in |
| Homarr | https://homarr.lab.jamilshaikh.in |
| Uptime Kuma | https://uptime.lab.jamilshaikh.in |
| MinIO | https://minio.lab.jamilshaikh.in |

### Talos Management

```bash
# Set Talos config
export TALOSCONFIG=talos-homelab-cluster/rendered/talosconfig

# Check cluster health
make talos-health

# View dashboard
make talos-dashboard

# View logs
make talos-logs
```

## Troubleshooting

### Layer 2 Failure (Talos Setup)

If Talos configuration fails:

```bash
# Retry Layer 2 without destroying VMs
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

# View Longhorn logs
kubectl logs -n longhorn-system -l app=longhorn-manager
```

### Storage Issues

```bash
# Check storage classes
kubectl get storageclass

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
```

## Makefile Commands

### Layer 0 - Templates
- `make create-templates` - Create both Debian 12 and Ubuntu 24.04 templates
- `make create-debian` - Create only Debian 12 template
- `make create-ubuntu` - Create only Ubuntu 24.04 template

### Deployment
- `make deploy` - Full 3-layer deployment
- `make layer1` - Deploy infrastructure (Terraform)
- `make layer2` - Configure Talos cluster (Ansible)
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
- `make destroy` - Destroy all Talos VMs (with confirmation)
- `make destroy-all` - Destroy VMs AND remove Talos config directory
- `make clean` - Clean temporary files

### Utilities
- `make help` - Show all available commands
- `make ping` - Ping all VMs and NFS server
- `make version` - Display tool versions
- `make setup-dns` - Add *.lab.jamilshaikh.in to /etc/hosts

## Security

- Talos secrets are **not committed** to Git (see [.gitignore](.gitignore))
- Use environment variables for Proxmox credentials
- ArgoCD credentials stored in Kubernetes secrets
- SSH keys managed via GitHub Secrets (for GitHub Actions)
- Longhorn encryption support ready (can be enabled via Helm values)
- Internal CA for TLS certificates (cert-manager + trust-manager)

## Monitoring

### Grafana Dashboards
- **Longhorn Dashboard**: Pre-configured for storage monitoring
- **Prometheus Stack**: Complete observability
- **Kubernetes Events**: Event dashboard
- **PostgreSQL**: Database monitoring
- **Loki**: Log exploration

Access Grafana:
```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Access at: http://localhost:3000
```

## Contributing

This is a personal showcase project, but feedback and suggestions are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - See [LICENSE](LICENSE) file for details

## Acknowledgments

- **Talos Linux**: For the amazing immutable Kubernetes OS
- **ArgoCD**: For declarative GitOps made easy
- **Longhorn**: For cloud-native distributed block storage

## Contact

For inquiries about this project or professional opportunities:

- GitHub: [@jamilshaikh07](https://github.com/jamilshaikh07)
- Project Link: [https://github.com/jamilshaikh07/talos-proxmox-gitops](https://github.com/jamilshaikh07/talos-proxmox-gitops)

---

**Built with care for showcasing DevOps/SRE skills**
