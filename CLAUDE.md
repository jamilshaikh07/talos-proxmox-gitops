# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Talos Proxmox GitOps — a 3-layer IaC solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, ArgoCD, and FluxCD.

- **Layer 1 (Infrastructure):** Terraform provisions Talos VMs on Proxmox (1 control plane + 1 worker) on isolated `vmbr2` LAN. OPNsense VM (ID 102) acts as the router — provisioned manually, not via Terraform.
- **Layer 2 (Configuration):** Ansible bootstraps a Talos Kubernetes cluster with Cilium CNI
- **Layer 3 (GitOps):** ArgoCD deploys ~19 Helm-based applications via app-of-apps pattern
- **Layer 3a (GitOps):** FluxCD runs side-by-side with ArgoCD, managing its own app set via HelmRelease + Kustomization

Key versions: Talos v1.12.6, Kubernetes v1.34.1, Cilium v1.16.5.

## Common Commands

```bash
# Full deployment (all 3 layers + DNS + CA trust)
make deploy

# Individual layers
make layer1                  # Terraform: create VMs
make layer2                  # Ansible: configure Talos cluster
make layer3                  # Ansible: deploy ArgoCD + apps
make layer3a                 # Ansible: bootstrap FluxCD (runs alongside ArgoCD)

# Partial deployments
make deploy-skip-layer1      # Layers 2-3 only (reuse existing VMs)
make deploy-skip-layer2      # Layers 1 and 3 only

# Cluster status
make status                  # Nodes + pods + ArgoCD apps
make status-apps             # ArgoCD sync status only
make talos-health            # Talos cluster health check

# Infrastructure management
make terraform-plan          # Preview infrastructure changes
make sync-inventory          # Regenerate Ansible inventory from Terraform outputs
make ping                    # Check connectivity to all VMs

# Access setup
make setup-homelab-access    # DNS (/etc/hosts) + CA certificate trust
make argocd-password         # Get ArgoCD admin password

# Cleanup
make destroy                 # Destroy VMs (with confirmation prompt)
make destroy-all             # Destroy VMs + remove Talos config directory
```

Run `make help` for the full list of targets.

## Architecture

### Directory Layout

- `terraform/proxmox-homelab/` — VM definitions, Talos ISO config, Proxmox provider. Uses Terraform Cloud workspace "alif".
- `ansible/` — Playbooks and roles for cluster configuration
  - `roles/talos-cluster/` — Core role: config generation, bootstrap, Cilium install, patches
  - `roles/gitops-deploy/` — ArgoCD Helm deployment
  - `roles/talos-cluster/vars/main.yml` — **Central cluster config** (node IPs, disks, versions)
  - `roles/talos-cluster/files/` — Talos machine config patches (CNI, kubelet certs, extensions, disk mounts)
- `gitops/` — GitOps application definitions
  - `app-of-apps.yaml` — ArgoCD entry point that auto-discovers all apps in `gitops/apps/`
  - `apps/` — Individual ArgoCD Application YAMLs (one per service)
  - `flux/` — FluxCD managed resources
    - `flux-system/` — GitRepository + root Kustomization bootstrap manifests
    - `apps/` — HelmRelease/Kustomization YAMLs managed by Flux (e.g. metrics-server)
  - `manifests/` — Kustomize/raw K8s manifests, including SOPS-encrypted secrets
- `scripts/` — `generate-ansible-inventory.py` bridges Terraform outputs to Ansible inventory
- `deploy-homelab.sh` — Master orchestration script (called by `make deploy` and CI)

### Key Design Patterns

**Terraform → Ansible bridge:** Terraform outputs are exported as JSON, then `scripts/generate-ansible-inventory.py` auto-generates Ansible inventory and node vars. All workers are now Proxmox VMs managed by Terraform.

**Talos patches:** Rather than monolithic machine configs, Talos uses patch files in `ansible/roles/talos-cluster/files/` applied during bootstrap: `cni.yaml`, `allowcontrolplanes.yaml`, `kubelet-certs.yaml`, `system-extensions.yaml`, `machine-features.yaml`.

**App-of-apps:** `gitops/app-of-apps.yaml` points to the `gitops/apps/` directory. Adding a new app = creating a new YAML file there. ArgoCD auto-syncs with prune and self-heal enabled.

**Storage:** local-path-provisioner (default StorageClass `local-path`) using `/var/local-path-storage` on the main OS disk of each node. Simple, zero-maintenance hostpath storage.

**Secrets:** SOPS with age encryption. Rules in `.sops.yaml` — encrypts `*.enc.yaml`, files in `gitops/manifests/secrets/`, and `gitops/manifests/autofix-dojo/*-secret.yaml`. Talos-generated secrets are gitignored.

### Network Layout

**Proxmox is physically hosted at a remote location (friend's office), accessible only via Tailscale.**

| Role | IP(s) |
|------|-------|
| Proxmox host | 10.20.0.10 (vmbr0, office LAN) · **100.127.198.7** (Tailscale) |
| Proxmox on cluster bridge | 192.168.60.2 (vmbr2) |
| OPNsense WAN | vmbr0 (office LAN, DHCP) |
| OPNsense LAN | 192.168.60.1 (vmbr2 — internal bridge) |
| Control plane (VM) | 192.168.60.40 |
| Worker 1 (VM) | 192.168.60.41 |
| MetalLB pool | 192.168.60.81-99 |
| Traefik LB / services | 192.168.60.81 |
| TrueNAS (home, backup) | 10.20.0.45 (home LAN) · **100.124.83.72** (Tailscale) |

All Talos VMs are on the internal `vmbr2` bridge (192.168.60.0/24), routed via OPNsense (VM 102).

#### Remote access

```bash
make tunnel   # SSH port-forward localhost:16443 → 192.168.60.40:6443 via Proxmox Tailscale
              # Required before using kubectl / talosctl from a non-office machine
```

`prox` SSH alias in `~/.ssh/config` targets `100.127.198.7` (Tailscale). Tailscale must be active on both
your local machine and Proxmox for any cluster access.

#### Backup path (Velero → TrueNAS MinIO)

Cluster pods cannot reach TrueNAS directly (different physical networks). Traffic routes via a socat
proxy running on Proxmox at `192.168.60.2:9900`, which forwards over Tailscale to TrueNAS MinIO at
`100.124.83.72:9900`. The proxy is a systemd service (`minio-proxy.service`) on Proxmox and starts
automatically on boot.

```
velero pod → 192.168.60.2:9900 (socat, Proxmox vmbr2)
           → 100.124.83.72:9900 (TrueNAS, Tailscale)
           → MinIO bucket: velero / backups/
```

Velero BackupStorageLocation `default` is configured with `s3Url: http://192.168.60.2:9900`.
Daily backups run at 02:30 UTC via the `daily-full` schedule.

## CI/CD

GitHub Actions workflow at `.github/workflows/deploy-homelab.yml` — manual dispatch with `skip_layer1`, `skip_layer2`, `skip_layer3` inputs. Runs on a `self-hosted` runner. Three sequential jobs matching the 3-layer architecture. Layer 2 auto-cleans up VMs on failure.

## Commit Style

```
type(scope): description
```

Examples: `fix(cloudflared): re-enable probes`, `feat(autofix-dojo): add SOPS-encrypted secret`, `chore(helm): critical upgrades`. Main branch is `master`.

## spinup.in — Hosted PaaS (DO NOT TOUCH)

**[spinup.in](https://spinup.in)** is a live, multi-tenant PaaS running on this cluster — a self-hosted Vercel clone.

- **Source code:** `~/workspace/homelab/100k/mvp/vercel-clone` — **never modify this via gitops repo tooling**
- **How it works:** GitHub webhook → Cloudflare Tunnel → Traefik → `control-plane` Go service → Kaniko build job → deploy to `paas-tenant-<username>` namespace
- **Self-healing CI:** push to `vercel-clone` main branch → control-plane redeploys itself within ~3 min

**Cluster namespaces (never delete any of these):**

| Namespace | Contents |
|-----------|----------|
| `paas-system` | `control-plane` Go service, `registry` (image push), `paas-db` CNPG cluster |
| `paas-deployments` | Kaniko build jobs + sample/test apps |
| `paas-tenant-<user>` | Live tenant app deployments (one namespace per user) |

The `paas-db` CNPG cluster in `paas-system` is the operational database for the control-plane. Deleting it = losing all tenant metadata.

## GitOps Rule — No Manual kubectl apply

**ArgoCD is the only deployment mechanism for everything in `gitops/`.** Never run `kubectl apply -f` on any file under `gitops/` directly. The correct flow is always:

```
edit file in gitops/ → git commit → git push → ArgoCD auto-syncs
```

This applies to: RBAC, manifests, ArgoCD apps, ingress routes, secrets (SOPS), everything. Manual applies create drift that ArgoCD will revert on next sync, or worse, silently diverge from git truth.

The only exceptions are **imperative secrets** (never in git) and **openclaw cron jobs** (stored in SQLite on PVC, edited via `openclaw cron edit`).

## Important Notes

- Talos configs in `talos-homelab-cluster/` are generated and gitignored — never commit them
- Terraform state is managed remotely via Terraform Cloud — `.tfstate` files are gitignored
- The `TALOSCONFIG` path used by Makefile is `/tmp/talos-homelab-cluster/rendered/talosconfig`
- Talos is an immutable OS with no SSH — use `talosctl` for all node interaction
- Version upgrades: update `talos_version` / `kubernetes_version` / `cilium_version` in `ansible/roles/talos-cluster/vars/main.yml`, then re-run Layer 2
- Adding new ArgoCD apps: create a YAML in `gitops/apps/`, it's auto-discovered by app-of-apps
- Adding new Flux apps: create a `HelmRelease` in `gitops/flux/apps/` and reference it in `gitops/flux/apps/kustomization.yaml`
- **OPNsense VM (ID 102):** Router for the Talos cluster. WAN on `vmbr0` (gets DHCP from office router), LAN on `vmbr2` (`192.168.60.1/24`). Provides DHCP with static reservations for Talos nodes (MAC-based). Managed manually — not in Terraform.
- **Flux kustomization `oee-sites-pnl`** is suspended — it managed pnl-postgres and homelab-postgres DR clusters which have been removed. Do not resume unless intentionally restoring those workloads.
- **Velero** is deployed out-of-band (not in ArgoCD/Flux). BSL points to `http://192.168.60.2:9900`. If the proxy goes down, SSH into `prox` and `systemctl restart minio-proxy`.
- **metrics-server** was removed from ArgoCD (`gitops/apps/metrics-server.yaml` deleted) — re-add if `kubectl top` is needed again.
