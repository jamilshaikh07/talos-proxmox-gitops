# Talos Proxmox GitOps

> **Production-Ready Homelab Infrastructure with Single-Click Deployment**

A complete Infrastructure-as-Code solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, and ArgoCD GitOps with zero-maintenance local storage.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Talos](https://img.shields.io/badge/Talos-v1.12.6-blue.svg)](https://www.talos.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.1-green.svg)](https://kubernetes.io/)

## Overview

This project demonstrates enterprise-grade infrastructure automation, showcasing skills in:

- **Infrastructure as Code** (Terraform)
- **Configuration Management** (Ansible)
- **Kubernetes** (Talos Linux v1.12.6 with Kubernetes v1.34.1)
- **GitOps** (ArgoCD + FluxCD hybrid, both running side-by-side)
- **Local Storage** (Rancher local-path-provisioner)
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
│  Infrastructure  │  ├─ OPNsense VM (router, vmbr0 WAN + vmbr2 LAN)
│                  │  ├─ 1x Talos Control Plane VM (100GB, 8GB RAM)
│                  │  └─ 1x Talos Worker VM (100GB, 16GB RAM)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible Configuration + Talos Setup
│  Configuration   │  ├─ Talos Cluster Bootstrap (v1.12.6)
│                  │  ├─ Cilium CNI Installation (v1.16.5)
│                  │  └─ Cert Rotation + KubePrism
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  GitOps Applications (via ArgoCD Helm)
│  GitOps          │  ├─ ArgoCD (Helm v7.7.12)
│  (ArgoCD)        │  ├─ local-path-provisioner (default StorageClass)
│                  │  ├─ cert-manager + trust-manager
│                  │  ├─ Traefik Ingress Controller
│                  │  ├─ MetalLB Load Balancer
│                  │  ├─ Prometheus Stack (Grafana + Alertmanager)
│                  │  ├─ Homarr (homelab dashboard)
│                  │  ├─ Uptime Kuma (service monitoring)
│                  │  ├─ Cloudflared (Cloudflare Tunnel)
│                  │  └─ More...
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3a        │  GitOps Applications (via FluxCD)
│  GitOps          │  ├─ Flux controllers (Helm OCI install)
│  (FluxCD)        │  ├─ GitRepository → this repo (master)
│                  │  └─ metrics-server (HelmRelease)
└──────────────────┘
```

## Features

### Core Infrastructure

- **Talos Linux Kubernetes**: Immutable, secure Kubernetes OS (v1.12.6)
- **Kubernetes v1.34.1**: Latest stable release
- **All-Proxmox Cluster**: Control plane VM + worker VM, both on Proxmox
- **Zero-Maintenance Storage**: Rancher local-path-provisioner using `/var/local-path-storage` on the OS disk
  - No extra disk required
  - Single default StorageClass: `local-path`
- **Failure Recovery**: Automatic Talos VM cleanup on configuration failure

### GitOps Applications

- **ArgoCD**: Declarative GitOps CD for Kubernetes (Helm-based deployment)
- **FluxCD**: GitOps controller running side-by-side with ArgoCD (manages metrics-server)
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
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/#talosctl) >= 1.12
- [Helm](https://helm.sh/docs/intro/install/) >= 3.12
- [flux CLI](https://fluxcd.io/flux/installation/) >= 2.0 (for layer3a)

**Infrastructure:**

- Proxmox VE 8.x server
- Network: OPNsense VM as router (WAN on `vmbr0`, LAN on `vmbr2` — `192.168.60.0/24`)
- Talos nodes on isolated internal subnet: `192.168.60.40-41`
- Storage: OS disk per node for local-path-provisioner (`/var/local-path-storage`)

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/jamilshaikh07/talos-proxmox-gitops.git
   cd talos-proxmox-gitops
   ```

2. **Configure Proxmox credentials**

   ```bash
   export TF_VAR_proxmox_api_url="https://your-proxmox-host:8006/api2/json"
   export TF_VAR_proxmox_api_token_id="root@pam!homelab"
   export TF_VAR_proxmox_api_token_secret="your-secret-token"
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
   make layer3  # GitOps (ArgoCD)
   make layer3a # GitOps (FluxCD)
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
| Proxmox host | 10.20.0.10 | Proxmox management (vmbr0) |
| OPNsense WAN | 10.20.0.x (DHCP) | Shared vmbr0 → home router |
| OPNsense LAN | 192.168.60.1 | Internal gateway (vmbr2) |
| Control Plane | 192.168.60.40 | Talos master node (VM) |
| Worker 1 | 192.168.60.41 | Talos worker node (VM, 16GB RAM) |
| MetalLB Pool | 192.168.60.81-99 | Load balancer IP range |
| Traefik LB | 192.168.60.81 | Ingress controller |
| k8s-gateway DNS | 192.168.60.82 | Internal DNS server |

### Storage Configuration

#### local-path-provisioner (DEFAULT)

- **Type**: Node-local block storage
- **StorageClass**: `local-path` (default, only StorageClass)
- **Disk Path**: `/var/local-path-storage` on each node (OS disk)
- **Reclaim Policy**: Retain
- **Binding Mode**: WaitForFirstConsumer (provisions when pod is scheduled)
- **Trade-off**: No replication — data lives on the node where the pod runs

### Node Disk Configuration

| Node | Install Disk | Storage Path |
|------|--------------|-------------|
| talos-cp-01 (VM) | /dev/sda | /var/local-path-storage |
| talos-wk-01 (VM) | /dev/sda | /var/local-path-storage |

### Talos Configuration

- **Talos Version**: v1.12.6
- **Kubernetes Version**: v1.34.1
- **Cluster Name**: homelab-cluster
- **Cluster Endpoint**: https://192.168.60.40:6443
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

With DNS configured (k8s-gateway at 192.168.60.82):

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
- `make layer3a` - Bootstrap Flux (FluxCD side-by-side)

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
