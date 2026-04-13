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
- **GitOps** (ArgoCD — app-of-apps pattern)
- **Local Storage** (Rancher local-path-provisioner)
- **CI/CD** (GitHub Actions)
- **Cloud Native Technologies** (Cilium, cert-manager, VictoriaMetrics, Cloudflare Tunnel, etc.)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TALOS PROXMOX GITOPS                         │
│                   3-Layer Architecture                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Layer 1         │  Terraform Infrastructure
│  Infrastructure  │  ├─ 1x Talos Control Plane VM (100GB, 8GB RAM)
│                  │  └─ 1x Talos Worker VM (100GB, 16GB RAM)
│                  │  (OPNsense router provisioned manually)
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible Configuration + Talos Setup
│  Configuration   │  ├─ Talos Cluster Bootstrap (v1.12.6)
│                  │  ├─ Cilium CNI Installation (v1.16.5)
│                  │  └─ KubePrism + kubelet cert rotation
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  GitOps Applications (ArgoCD app-of-apps)
│  GitOps          │  ├─ ArgoCD (self-managed via Helm)
│  (ArgoCD)        │  ├─ MetalLB + Traefik (load balancing + ingress)
│                  │  ├─ cert-manager + trust-manager (internal CA)
│                  │  ├─ Cilium (day-2 config)
│                  │  ├─ CoreDNS k8s-gateway (internal DNS)
│                  │  ├─ external-dns (Cloudflare DNS automation)
│                  │  ├─ Cloudflared (Zero Trust tunnel)
│                  │  ├─ VictoriaMetrics stack (Grafana + metrics)
│                  │  ├─ Uptime Kuma (service monitoring)
│                  │  ├─ Trivy Operator (security scanning)
│                  │  ├─ local-path-provisioner (default StorageClass)
│                  │  └─ metrics-server
└──────────────────┘

### External Access Flow

```
Internet → Cloudflare Edge (TLS) → cloudflared pods → http://Traefik:80 → backend
```

### Internal Access Flow (LAN only)

```
Browser → /etc/hosts → 192.168.60.81 (Traefik) → backend
```
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

### GitOps Applications (all managed by ArgoCD)

| App | Version | Purpose |
|-----|---------|-------|
| ArgoCD | Helm v7.7.12 | GitOps controller (self-managed) |
| MetalLB | latest | Bare-metal load balancer |
| Traefik | v39.x | Ingress controller (VIP: `192.168.60.81`) |
| Cilium | v1.16.5 | eBPF CNI + network policy |
| cert-manager | v1.20.1 | Internal CA + TLS automation |
| trust-manager | latest | CA bundle distribution |
| CoreDNS k8s-gateway | latest | Internal DNS (`*.lab.jamilshaikh.in → 192.168.60.81`) |
| external-dns | v0.20.0 | Auto-manage Cloudflare DNS records |
| Cloudflared | latest | Cloudflare Zero Trust tunnel |
| VictoriaMetrics stack | v0.72.6 | Prometheus-compatible metrics + Grafana |
| Uptime Kuma | v2.22.0 | Service uptime monitoring |
| Trivy Operator | latest | In-cluster security scanning |
| local-path-provisioner | latest | Default StorageClass (`local-path`) |
| metrics-server | 3.13.0 | Kubernetes resource metrics (HPA/VPA) |

### Automation

- **Single-Command Deployment**: `make deploy` runs all 3 layers end-to-end
- **Idempotent**: Safe to run multiple times
- **Self-Healing**: ArgoCD auto-syncs with prune + self-heal enabled
- **CI/CD**: GitHub Actions workflow with layer-level skip inputs (self-hosted runner)
- **Scale Workflow**: Terraform-driven worker count and VM sizing with inventory regeneration helpers

## Quick Start

### Prerequisites

**Required Software:**

- [Terraform](https://www.terraform.io/downloads) >= 1.9.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.15
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/#talosctl) >= 1.12
- [Helm](https://helm.sh/docs/intro/install/) >= 3.12

**Infrastructure:**

- Proxmox VE 8.x server
- OPNsense VM as router: WAN on `vmbr0`, LAN on `vmbr2` (`192.168.60.1/24`)
- Talos nodes on isolated internal subnet: `192.168.60.40` (CP), `192.168.60.41` (worker)
- Terraform Cloud workspace `alif` (for remote state)

**Pre-deploy secrets** (must be applied manually after Layer 3):

```bash
# 1. Cloudflare API token (for external-dns)
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=<YOUR_CF_API_TOKEN> \
  -n external-dns

# 2. Cloudflare Tunnel credentials (locally-managed tunnel)
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=~/.cloudflared/<tunnel-id>.json \
  -n cloudflared
```

> The tunnel credentials JSON is created by `cloudflared tunnel create <name>` at
> `~/.cloudflared/<tunnel-id>.json`. Update `tunnel:` in
> `gitops/manifests/cloudflared/deployment.yaml` with your tunnel ID.

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

3. **Deploy all layers**

   ```bash
   make deploy
   # Or layer by layer:
   make layer1   # Terraform: create VMs
   make layer2   # Ansible: bootstrap Talos cluster
   make layer3   # Ansible: deploy ArgoCD + app-of-apps
   ```

4. **Apply pre-deploy secrets** (see Prerequisites above)

5. **Configure local workstation access**

   ```bash
   make setup-homelab-access
   # Adds /etc/hosts entries for internal .lab. domains + trusts the internal CA cert
   ```

### Deployment Time

- **Layer 1** (Infrastructure): ~5 minutes
- **Layer 2** (Talos bootstrap): ~10 minutes
- **Layer 3** (ArgoCD + apps sync): ~10 minutes

**Total: ~25 minutes**

## Network Configuration

| Component | IP Address | Description |
|-----------|------------|-------------|
| Proxmox host | 10.20.0.10 | Proxmox management (vmbr0) |
| OPNsense WAN | 10.20.0.x (DHCP) | Shared vmbr0 → home router |
| OPNsense LAN | 192.168.60.1 | Internal gateway (vmbr2) |
| Control Plane | 192.168.60.40 | Talos master node |
| Worker 1 | 192.168.60.41 | Talos worker node |
| MetalLB Pool | 192.168.60.81–99 | Load balancer IP range |
| Traefik VIP | 192.168.60.81 | Ingress controller |
| k8s-gateway VIP | 192.168.60.82 | Internal DNS server |

## Service Access

### Public (via Cloudflare Tunnel — accessible from anywhere)

| Service | URL |
|---------|-----|
| ArgoCD | https://argocd.jamilshaikh.in |
| Grafana | https://grafana.jamilshaikh.in |
| Uptime Kuma | https://uptime.jamilshaikh.in |

### Internal (LAN only — requires `make setup-homelab-access` or OPNsense DNS)

| Service | URL |
|---------|-----|
| Traefik dashboard | http://traefik.lab.jamilshaikh.in |
| Prometheus/VictoriaMetrics | http://prometheus.lab.jamilshaikh.in |

> Internal services use HTTP (port 80) via Traefik's `web` entrypoint. To add a new internal
> service: create an IngressRoute on the `web` entrypoint with a `*.lab.jamilshaikh.in` hostname,
> then add it to `setup-dns` in the Makefile.

## Storage

- **StorageClass**: `local-path` (default, only StorageClass in the cluster)
- **Path**: `/var/local-path-storage` on each node's OS disk
- **Binding**: WaitForFirstConsumer
- **Trade-off**: No replication — data lives on the node where the pod schedules

| Node | Install Disk | Storage Path |
|------|--------------|-------------|
| talos-cp-01 | /dev/sda | /var/local-path-storage |
| talos-wk-01 | /dev/sda | /var/local-path-storage |

## Scaling and Resize

The cluster now supports two Terraform-driven scale paths:

- Horizontal scaling by changing the number of Talos worker VMs.
- Vertical scaling by changing the CPU, memory, or disk size assigned to the control plane or workers.

### Important constraints

- Talos node IPs are still DHCP-based. Terraform now emits deterministic MAC and planned IP pairs, but you must keep the matching OPNsense DHCP reservations intact.
- Scale-down is not automatic for stateful workloads. Because the cluster uses `local-path`, any PVC bound to a node being removed must be migrated or deleted first.
- Shrinking `WORKER_COUNT` removes the highest-numbered worker first. Drain that node before applying Terraform.

### Plan a scale change

```bash
# Add a second worker with a smaller footprint than the current default
make scale-plan WORKER_COUNT=2 WORKER_MEMORY=8192 WORKER_CORES=2

# Resize the existing control plane and worker shapes
make scale-plan CONTROL_PLANE_MEMORY=12288 WORKER_MEMORY=12288 WORKER_CORES=4
```

### Apply a scale change

```bash
make scale-apply WORKER_COUNT=2 WORKER_MEMORY=8192 WORKER_CORES=2
make planned-dhcp
make layer2
```

`make planned-dhcp` prints the MAC/IP reservations that should exist on OPNsense for each Talos VM.

### Safe worker scale-down

```bash
make drain-node NODE=talos-wk-02
make scale-apply WORKER_COUNT=1
```

If the node still hosts pods backed by `local-path` PVCs, move or retire that workload first. Draining alone does not preserve node-local data.

## Talos Configuration

- **Version**: v1.12.6 | **Kubernetes**: v1.34.1 | **CNI**: Cilium v1.16.5
- **Cluster endpoint**: `https://192.168.60.40:6443`
- **Talosconfig path**: `talos-homelab-cluster/rendered/talosconfig` (gitignored)

Machine config patches in `talos-homelab-cluster/` (config only, no secrets):

| File | Purpose |
|------|--------|
| `cni.yaml` | Disable built-in CNI (Cilium installs instead) |
| `allowcontrolplanes.yaml` | Allow workloads on control plane |
| `kubelet-certs.yaml` | Enable kubelet cert rotation |
| `system-extensions.yaml` | qemu-guest-agent + iscsi-tools via image factory |
| `machine-features.yaml` | KubePrism local API load balancer |
| `controlplane-machine.yaml` | CP hostname + disk |
| `talos-wk-01-machine.yaml` | Worker hostname + disk |

## Management Commands

### Deployment
```bash
make deploy                # Full 3-layer deployment
make deploy-skip-layer1    # Layers 2+3 only (reuse existing VMs)
make deploy-skip-layer2    # Layers 1+3 only
make layer1                # Terraform only
make layer2                # Talos bootstrap only
make layer3                # ArgoCD + GitOps only
```

### Cluster Status
```bash
make status                # Nodes + pods + ArgoCD apps
make status-apps           # ArgoCD sync status only
make talos-health          # Talos cluster health
make ping                  # Connectivity check to all VMs
```

### Access
```bash
make argocd-password       # Get ArgoCD admin password
make argocd-port-forward   # Port-forward ArgoCD UI → localhost:8080
make setup-homelab-access  # /etc/hosts entries + trust internal CA
make kubeconfig            # Display KUBECONFIG path
```

### Cleanup
```bash
make destroy               # Destroy VMs (with confirmation prompt)
make destroy-all           # Destroy VMs + remove Talos config dir
```

### Utilities
```bash
make help                  # Full command list with descriptions
make help-when             # Scenario runbook (what to run when)
make version               # Tool versions
make terraform-plan        # Preview infrastructure changes
make sync-inventory        # Regenerate Ansible inventory from Terraform outputs
```

### What To Run When

```bash
# I want a full clean deployment
make deploy

# I changed Terraform and want infra updates only
make terraform-plan
make layer1
make sync-inventory

# I changed Talos/Ansible and want to reconcile cluster config
make layer2

# I changed GitOps manifests/apps and want app reconciliation
make layer3

# I want to scale workers or resize VM resources
make scale-plan WORKER_COUNT=2 WORKER_MEMORY=8192 WORKER_CORES=2
make scale-apply WORKER_COUNT=2 WORKER_MEMORY=8192 WORKER_CORES=2
make planned-dhcp
make layer2

# I want a safe worker scale-down
make drain-node NODE=talos-wk-02
make scale-apply WORKER_COUNT=1
make layer2

# I just need health and sync checks
make status
make status-apps
make talos-health
```

`make --help` shows GNU Make's built-in help, not project runbooks. Use `make help` and `make help-when` for homelab-specific guidance.

## Troubleshooting

### Layer 2 Failure

```bash
make layer2                    # Retry without destroying VMs
make destroy && make deploy    # Full reset if needed
```

### ArgoCD App out of sync

```bash
export KUBECONFIG=~/.kube/config-homelab
kubectl get applications -n argocd
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

### Cloudflared not connecting

The tunnel is locally-managed (CLI-created, not dashboard). Credentials live in the
`cloudflared-credentials` secret in the `cloudflared` namespace:

```bash
# Check logs
kubectl logs -n cloudflared -l app=cloudflared --tail=50

# Recreate credentials secret
kubectl delete secret cloudflared-credentials -n cloudflared
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=~/.cloudflared/<tunnel-id>.json \
  -n cloudflared
kubectl rollout restart deployment/cloudflared -n cloudflared
```

### Internal DNS not resolving

`*.lab.jamilshaikh.in` resolves via CoreDNS k8s-gateway at `192.168.60.82`. Use
`make setup-homelab-access` on your workstation, or configure OPNsense Unbound to forward
`lab.jamilshaikh.in → 192.168.60.82` for LAN-wide resolution.



## Security Notes

- Talos secrets (`secrets.yaml`, `rendered/`) are **gitignored** — never committed
- Terraform state is remote (Terraform Cloud) — `.tfstate` files are gitignored
- Cloudflare API token and tunnel credentials are **not in Git** — applied manually post-deploy
- Internal TLS via cert-manager (self-signed root CA → homelab-ca issuer)
- Talos has no SSH — all node interaction via `talosctl`

## CI/CD

GitHub Actions at `.github/workflows/deploy-homelab.yml`:
- Manual dispatch with `skip_layer1`, `skip_layer2`, `skip_layer3` boolean inputs
- Runs on a self-hosted runner on the Proxmox host
- Three sequential jobs matching the 3-layer architecture
- Layer 2 auto-cleans up VMs on failure

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- **Talos Linux** — immutable, API-driven Kubernetes OS
- **ArgoCD** — declarative GitOps made easy
- **Rancher local-path-provisioner** — zero-maintenance local storage

## Contact

- GitHub: [@jamilshaikh07](https://github.com/jamilshaikh07)
- Project: [github.com/jamilshaikh07/talos-proxmox-gitops](https://github.com/jamilshaikh07/talos-proxmox-gitops)

---

*Built for showcasing DevOps/SRE skills*
