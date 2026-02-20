# Talos Proxmox GitOps

> **Production-Ready Homelab Infrastructure with Single-Click Deployment**

A complete Infrastructure-as-Code solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, and ArgoCD GitOps with zero-maintenance local storage.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Talos](https://img.shields.io/badge/Talos-v1.11.5-blue.svg)](https://www.talos.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.1-green.svg)](https://kubernetes.io/)

## Overview

This project demonstrates enterprise-grade infrastructure automation, showcasing skills in:

- **Infrastructure as Code** (Terraform)
- **Configuration Management** (Ansible)
- **Kubernetes** (Talos Linux v1.11.5 with Kubernetes v1.34.1)
- **GitOps** (ArgoCD with Helm)
- **Local Storage** (Rancher local-path-provisioner)
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
│  Infrastructure  │  ├─ 1x Talos Control Plane VM (50GB OS + 500GB data)
│                  │  ├─ 3x Talos Worker VMs (50GB OS + 500GB data each)
│                  │  └─ 1x Bare Metal Worker (optional)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible Configuration + Talos Setup
│  Configuration   │  ├─ Talos Cluster Bootstrap (v1.11.5)
│                  │  ├─ Extra disk mounted at /var/mnt/longhorn
│                  │  ├─ Cilium CNI Installation (v1.16.5)
│                  │  └─ Metrics Server + Cert Rotation
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  GitOps Applications (via ArgoCD Helm)
│  GitOps          │  ├─ ArgoCD (Helm v7.7.12)
│                  │  ├─ local-path-provisioner (default StorageClass)
│                  │  ├─ Metrics Server (Talos-compatible)
│                  │  ├─ cert-manager + trust-manager
│                  │  ├─ Traefik Ingress Controller
│                  │  ├─ MetalLB Load Balancer
│                  │  ├─ Prometheus Stack (Grafana + Alertmanager)
│                  │  ├─ Homarr (homelab dashboard, SQLite)
│                  │  ├─ Uptime Kuma (service monitoring)
│                  │  ├─ Cloudflared (Cloudflare Tunnel)
│                  │  └─ More...
└──────────────────┘
```

## Features

### Core Infrastructure

- **Talos Linux Kubernetes**: Immutable, secure Kubernetes OS (v1.11.5)
- **Kubernetes v1.34.1**: Latest stable release
- **Hybrid Cluster**: VM workers + optional bare metal workers
- **Zero-Maintenance Storage**: Rancher local-path-provisioner using dedicated extra disks
  - Extra disk mounted at `/var/mnt/longhorn` on each node
  - No replication overhead — simple and fast local storage
  - Single default StorageClass: `local-path`
- **Failure Recovery**: Automatic Talos VM cleanup on configuration failure

### GitOps Applications

- **ArgoCD**: Declarative GitOps CD for Kubernetes (Helm-based deployment)
- **local-path-provisioner**: Zero-maintenance local block storage (default StorageClass)
- **Metrics Server**: Kubernetes resource metrics (Talos-compatible)
- **cert-manager**: Automatic SSL certificate management
- **trust-manager**: CA bundle distribution across namespaces
- **Traefik**: Modern HTTP/HTTPS ingress controller
- **MetalLB**: Load balancer for bare-metal Kubernetes
- **Prometheus Stack**: Complete observability (Prometheus + Grafana + Alertmanager)
- **Homarr**: Homelab dashboard (SQLite backend)
- **Uptime Kuma**: Service uptime monitoring
- **Cloudflared**: Cloudflare Tunnel for secure external access
- **Cilium v1.16.5**: eBPF-based CNI with network policy
- **CoreDNS k8s-gateway**: Internal DNS for `*.lab.jamilshaikh.in`
- **external-dns**: Automatic DNS record management
- **reflector**: Secret/ConfigMap replication across namespaces

### Automation

- **Single-Click Deployment**: Via Makefile or local script
- **3-Layer Architecture**: Clean separation of concerns
- **Idempotent**: Safe to run multiple times
- **Self-Healing**: ArgoCD automatically syncs application state
- **Template Creation**: Automated Debian 12 and Ubuntu 24.04 cloud-init templates
- **Bare Metal Auto-Detection**: Auto-detect disks on bare metal nodes via talosctl
- **autofix-dojo**: Automated Helm chart upgrade PRs (like Dependabot for Helm)

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
- Storage: Extra disk per node for local-path-provisioner (500GB recommended)

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/jamilshaikh07/talos-proxmox-gitops.git
   cd talos-proxmox-gitops
   ```

2. **Configure Proxmox credentials**

   ```bash
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
| MetalLB Pool | 10.20.0.81-99 | Load balancer IP range |
| Traefik LB | 10.20.0.81 | Ingress controller |
| k8s-gateway DNS | 10.20.0.82 | Internal DNS server |

### Storage Configuration

#### local-path-provisioner (DEFAULT)

- **Type**: Node-local block storage
- **StorageClass**: `local-path` (default, only StorageClass)
- **Disk Path**: `/var/mnt/longhorn` on each node (extra disk mounted by Talos)
- **Reclaim Policy**: Retain
- **Binding Mode**: WaitForFirstConsumer (provisions when pod is scheduled)
- **Trade-off**: No replication — data lives on the node where the pod runs

> **Note**: The mount path `/var/mnt/longhorn` is the disk mount point configured in the Talos machine config, retained from the original setup. It is unrelated to Longhorn.

### Node Disk Configuration

| Node | Install Disk | Data Disk | Mount Path |
|------|--------------|-----------|------------|
| talos-cp-01 (VM) | /dev/sda | /dev/sdb | /var/mnt/longhorn |
| talos-wk-01 (VM) | /dev/sda | /dev/sdb | /var/mnt/longhorn |
| talos-wk-02 (VM) | /dev/sda | /dev/sdb | /var/mnt/longhorn |
| talos-wk-03 (VM) | /dev/sda | /dev/sdb | /var/mnt/longhorn |
| talos-wk-04 (Bare Metal) | /dev/nvme0n1 | /dev/sda | /var/mnt/longhorn |

### Adding Bare Metal Workers

```bash
# Auto-detect disks on a new bare metal node
./scripts/generate-ansible-inventory.py --baremetal-ip 10.20.0.45

# Auto-detect disks on existing bare metal nodes in config
./scripts/generate-ansible-inventory.py --detect-baremetal-disks

# Specify custom hostname
./scripts/generate-ansible-inventory.py --baremetal-ip 10.20.0.45 --baremetal-hostname talos-wk-05
```

### Talos Configuration

- **Talos Version**: v1.11.5
- **Kubernetes Version**: v1.34.1
- **Cluster Name**: homelab-cluster
- **Cluster Endpoint**: https://10.20.0.40:6443
- **CNI**: Cilium v1.16.5
- **Allow Control Plane Scheduling**: Yes
- **Metrics Server**: Enabled (with kubelet cert rotation)

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

### Access Services via Ingress

With DNS configured (k8s-gateway at 10.20.0.82):

| Service | URL |
|---------|-----|
| Grafana | https://grafana.lab.jamilshaikh.in |
| ArgoCD | https://argocd.lab.jamilshaikh.in |
| Prometheus | https://prometheus.lab.jamilshaikh.in |
| Traefik | https://traefik.lab.jamilshaikh.in |
| Homarr | https://homarr.lab.jamilshaikh.in |
| Uptime Kuma | https://uptime.lab.jamilshaikh.in |

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

```bash
# Retry Layer 2 without destroying VMs
make layer2

# Or destroy everything and start fresh
make destroy
make deploy
```

### Storage Issues

```bash
# Check storage class (should only be local-path)
kubectl get storageclass

# Check PVC status
kubectl get pvc -A

# Check provisioner logs
kubectl logs -n local-path-provisioner -l app.kubernetes.io/name=local-path-provisioner

# Test PVC provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-pvc
```

> **Note**: The `local-path-provisioner` namespace requires `pod-security.kubernetes.io/enforce: privileged` because its helper pods use hostPath volumes to create directories on nodes.

### Cloudflared Issues

If cloudflared is in CrashLoopBackOff with `Unauthorized: Invalid tunnel secret`:

1. Go to [Cloudflare Zero Trust Dashboard](https://one.cloudflare.com) → Networks → Tunnels
2. Select your tunnel → Configure → regenerate the token
3. Update the `cloudflared-tunnel-token` secret in the `cloudflared` namespace

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
- `make ping` - Ping all VMs
- `make version` - Display tool versions
- `make setup-homelab-access` - Add DNS entries and trust CA certificate

## Security

- Talos secrets are **not committed** to Git (see [.gitignore](.gitignore))
- Use environment variables for Proxmox credentials
- ArgoCD credentials stored in Kubernetes secrets
- SSH keys managed via GitHub Secrets (for GitHub Actions)
- SOPS with age encryption for Kubernetes secrets in Git
- Internal CA for TLS certificates (cert-manager + trust-manager)

## Monitoring

### Grafana Dashboards

Pre-configured dashboards in `gitops/manifests/grafana-dashboards/`:

- **Kubernetes Cluster**: Node CPU, memory, and pod metrics
- **Kubernetes Nodes**: Per-node resource utilization

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
- **Rancher local-path-provisioner**: For simple, zero-maintenance local storage

## Contact

For inquiries about this project or professional opportunities:

- GitHub: [@jamilshaikh07](https://github.com/jamilshaikh07)
- Project Link: [https://github.com/jamilshaikh07/talos-proxmox-gitops](https://github.com/jamilshaikh07/talos-proxmox-gitops)

---

**Built with care for showcasing DevOps/SRE skills**
