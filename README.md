# Talos Proxmox GitOps

> **Production homelab running real workloads, GitOps-managed, AI SRE-monitored.**

A 3-layer IaC stack (Terraform + Ansible + ArgoCD) on Proxmox running Talos Linux Kubernetes. This isn't a demo: it hosts live products, including [spinup.in](https://spinup.in) (self-hosted PaaS), [belapurpremierleague.com](https://belapurpremierleague.com) (production sports league site), [KubeWise](https://github.com/jamilshaikh08/kubewise) (K8s cost advisor), openclaw AI SRE, and Mattermost for team comms.

[![Talos](https://img.shields.io/badge/Talos-v1.12.6-blue.svg)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.1-green.svg)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9+-purple.svg)](https://www.terraform.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## What runs here

### Live products

| Product | URL | What it is |
|---|---|---|
| **spinup.in** | [spinup.in](https://spinup.in) | Self-hosted Vercel clone: push to GitHub, get a live URL |
| **Belapur Premier League** | [belapurpremierleague.com](https://belapurpremierleague.com) | Production sports league site (internally: `bpl-prod` app) |
| **KubeWise** | [github.com/jamilshaikh08/kubewise](https://github.com/jamilshaikh08/kubewise) | K8s cost & performance advisor |
| **Mattermost** | [mattermost.jamilshaikh.in](https://mattermost.jamilshaikh.in) | Self-hosted team comms, openclaw bot delivery target |
| **ArgoCD** | [argocd.jamilshaikh.in](https://argocd.jamilshaikh.in) | GitOps controller UI, GitHub SSO |
| **Grafana** | [grafana.jamilshaikh.in](https://grafana.jamilshaikh.in) | Metrics dashboards |
| **Uptime Kuma** | [uptime.jamilshaikh.in](https://uptime.jamilshaikh.in) | Service uptime monitoring |
| **Coder** | [code.jamilshaikh.in](https://code.jamilshaikh.in) | Self-hosted dev environments |
| **Teleport** | [teleport.jamilshaikh.in](https://teleport.jamilshaikh.in) | Browser/audited SSH + kubectl access proxy |

ArgoCD, Grafana, and Teleport are gated by Cloudflare Access (GitHub SSO) on top of their own auth.

### Platform stack (ArgoCD app-of-apps, 27 apps)

| App | Purpose |
|---|---|
| ArgoCD | GitOps controller (self-managed) |
| MetalLB + Traefik | Bare-metal LB + ingress (VIP: `192.168.60.81`) |
| Cilium v1.16.5 | eBPF CNI + network policy |
| cert-manager + trust-manager | Internal CA + TLS automation |
| CoreDNS k8s-gateway | Internal DNS (`*.lab.jamilshaikh.in`) |
| external-dns + Cloudflared | Cloudflare DNS automation + Zero Trust tunnel |
| CloudNativePG | PostgreSQL operator (mattermost-db, paas-db, coder-db) |
| VictoriaMetrics + Grafana | Metrics stack |
| Loki + Promtail | Log aggregation to MinIO |
| MinIO | S3-compatible object storage (logs, backups) |
| Uptime Kuma | Service uptime monitoring |
| Trivy Operator | In-cluster security scanning |
| local-path-provisioner | Default StorageClass (`local-path`) |
| Mattermost | Self-hosted team chat |
| openclaw | AI SRE agent (see below) |
| KubeWise | K8s cost advisor |
| bpl-prod | Belapur Premier League production site |
| Coder | Self-hosted dev environments |
| Teleport | Access proxy: browser/audited SSH + kubectl |

### Out-of-band (not in ArgoCD)

| Component | Purpose |
|---|---|
| Velero | Cluster backups to TrueNAS MinIO via Tailscale proxy |
| spinup.in PaaS | `paas-system` / `paas-deployments` / `paas-tenant-*`, self-rebuilding, see below |

---

## AI SRE: openclaw

The cluster watches itself. openclaw runs as a pod in the `openclaw` namespace, posts to Mattermost `#devops`, and handles both automated remediation and interactive runbooks.

**Phase 1, Monitoring:** crons every 10-30 min watching pods, ArgoCD apps, PaaS health, BPL prod
**Phase 2, Remediation:** auto-deletes Pending/CrashLoop pods, approval-gated ArgoCD sync + rollout restart
**Phase 3, Runbook Intelligence:** incident correlation, capacity forecasting, automated postmortems, drain/sync/log runbooks, spinup.in PaaS awareness

Model: `deepseek/deepseek-v4-flash` (primary, DeepSeek's OpenAI-compatible endpoint). Full architecture in [`docs/07-openclaw-ai-sre.md`](docs/07-openclaw-ai-sre.md).

**Active crons:**

| Cron | Fires | Behaviour |
|---|---|---|
| `critical-alert-check` | every 15m | Auto-deletes CrashLoop pods |
| `paas-health-check` | every 10m | spinup.in PaaS health, quiet mode, alerts only on degradation |
| `bpl-health-check` | every 10m | BPL prod health, quiet mode, alerts only on degradation |
| `argocd-sync-check` | every 30m | ArgoCD drift, approval-gated sync |
| `incident-correlator` | every 30m | Correlates multi-signal incidents |
| `cluster-health-check` | every 1h | Pending pod auto-fix + postmortem |
| `capacity-forecast` | Mon 8am IST | Weekly CPU/memory/PVC risk report |

---

## Architecture

```
┌──────────────────┐
│  Layer 1         │  Terraform → Proxmox
│  Infrastructure  │  ├─ 1× Control Plane VM (talos-cp-01, 192.168.60.40)
│                  │  └─ 1× Worker VM (talos-wk-01, 192.168.60.41)
└─────────┬────────┘  OPNsense router (VM 102), provisioned manually
          │
┌─────────▼────────┐
│  Layer 2         │  Ansible → Talos
│  Configuration   │  ├─ Talos cluster bootstrap (v1.12.6)
│                  │  ├─ Cilium CNI (v1.16.5)
│                  │  └─ KubePrism + kubelet cert rotation
└─────────┬────────┘
          │
┌─────────▼────────┐
│  Layer 3         │  ArgoCD app-of-apps → gitops/apps/
│  GitOps          │  └─ 27 apps, auto-sync, prune + self-heal
└──────────────────┘
```

**GitOps rule:** All manifest changes go through git, push, ArgoCD. No manual `kubectl apply` on anything in `gitops/`. Exceptions: imperative secrets (never in git) and openclaw cron SQLite edits.

### Network

| Role | IP |
|---|---|
| Proxmox host | 10.20.0.10 (LAN) / 100.127.198.7 (Tailscale) |
| OPNsense LAN | 192.168.60.1 (vmbr2 gateway) |
| Control Plane | 192.168.60.40 |
| Worker | 192.168.60.41 |
| Traefik VIP | 192.168.60.81 |
| k8s-gateway DNS | 192.168.60.82 |
| MetalLB pool | 192.168.60.81-99 |

> Proxmox is at a remote location (friend's office). All cluster access requires Tailscale + `make tunnel`.

### Access flows

```
# Public (anywhere)
Internet → Cloudflare Edge → cloudflared pod → Traefik → backend

# Internal (LAN / tunnel)
Browser → /etc/hosts → 192.168.60.81 (Traefik) → backend
```

---

## spinup.in: Production PaaS

**[spinup.in](https://spinup.in)** is a self-hosted Vercel clone running on this cluster.

- **Source:** `~/workspace/homelab/100k/mvp/vercel-clone`, never touch via this repo's tooling
- **Flow:** GitHub webhook → Cloudflare Tunnel → Traefik → `control-plane` Go service → Kaniko build → `paas-tenant-<user>` namespace
- **Self-healing:** push to vercel-clone `main`, control-plane redeploys in ~3 min
- **Database:** `paas-db` CNPG cluster in `paas-system`; losing it means losing all tenant metadata

> **Never delete `paas-*` namespaces or the `paas-db` CNPG cluster.**

---

## Quick Start

### Prerequisites

- Terraform >= 1.9, Ansible >= 2.15, kubectl >= 1.28, talosctl >= 1.12, Helm >= 3.12
- Proxmox VE 8.x with OPNsense VM (WAN: `vmbr0`, LAN: `vmbr2` at `192.168.60.1/24`)
- Terraform Cloud workspace `alif` (remote state)
- Tailscale active on both local machine and Proxmox

### Deploy

```bash
git clone https://github.com/jamilshaikh07/talos-proxmox-gitops.git
cd talos-proxmox-gitops

make deploy          # Full 3-layer deployment (~25 min)
make tunnel          # SSH tunnel for kubectl access (required from non-office machines)
make setup-homelab-access   # /etc/hosts + trust internal CA
```

### Layer by layer

```bash
make layer1          # Terraform: create VMs
make layer2          # Ansible: bootstrap Talos + Cilium
make layer3          # Ansible: deploy ArgoCD + app-of-apps
make layer3a         # Ansible: bootstrap FluxCD (side-by-side)
```

### Status

```bash
make status          # Nodes + pods + ArgoCD apps
make status-apps     # ArgoCD sync status only
make talos-health    # Talos cluster health
make argocd-password # Get ArgoCD admin password
```

### Cleanup

```bash
make destroy         # Destroy VMs (with confirmation)
make destroy-all     # Destroy VMs + remove Talos config dir
```

---

## Storage

Single StorageClass: `local-path` (Rancher local-path-provisioner). Data lives on the node, no replication. Scale-down requires migrating or retiring any PVC on the removed node first.

| Node | Disk | Storage path |
|---|---|---|
| talos-cp-01 | /dev/sda | /var/local-path-storage |
| talos-wk-01 | /dev/sda | /var/local-path-storage |

---

## Security

- Talos secrets and rendered configs are gitignored, never committed
- Terraform state is remote (Terraform Cloud), no `.tfstate` in git
- Cloudflare API token + tunnel credentials applied manually post-deploy
- Internal TLS via cert-manager (self-signed root CA to homelab-ca issuer)
- Talos has no SSH; all node interaction via `talosctl`
- Secrets are imperative only (`kubectl create secret`), never committed to git
- Cloudflare Access (GitHub SSO) gates ArgoCD, Grafana, and Teleport at the edge

---

## Docs

Full behind-the-scenes decisions in [`docs/`](docs/):

| Doc | What it covers |
|---|---|
| [Cluster Foundation](docs/01-cluster-foundation.md) | Talos + Proxmox + Terraform + Ansible, why this stack |
| [GitOps Layer](docs/02-gitops-layer.md) | ArgoCD + FluxCD side-by-side, app-of-apps pattern |
| [Networking](docs/03-networking.md) | OPNsense, MetalLB, Traefik, Cloudflare tunnel, external-dns |
| [Observability](docs/04-observability.md) | VictoriaMetrics, Loki, Promtail, Grafana, Uptime Kuma |
| [Storage & Backups](docs/05-storage-backups.md) | local-path, MinIO, Velero, CNPG barman |
| [spinup.in PaaS](docs/06-spinup-paas.md) | Self-hosted Vercel clone, architecture, live tenant workloads |
| [openclaw AI SRE](docs/07-openclaw-ai-sre.md) | AI SRE agent, cron architecture, Phase 1-3, model chain |
| [kagent AI Agents](docs/08-kagent-ai-agents.md) | Cluster-native AI agents (currently disabled, see doc for why) |
| [Access Control & SSO](docs/09-access-control-sso.md) | Cloudflare Access, ArgoCD Dex GitHub SSO |

---

## CI/CD

GitHub Actions at `.github/workflows/deploy-homelab.yml`:
- Manual dispatch with `skip_layer1` / `skip_layer2` / `skip_layer3` inputs
- Self-hosted runner on Proxmox host
- Layer 2 auto-cleans VMs on failure

---

## License

MIT, see [LICENSE](LICENSE).

---

*Senior SRE homelab, built to run real products, not just demos.*
