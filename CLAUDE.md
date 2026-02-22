# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Talos Proxmox GitOps — a 3-layer IaC solution for deploying a Kubernetes homelab on Proxmox using Talos Linux, Terraform, Ansible, and ArgoCD.

- **Layer 1 (Infrastructure):** Terraform provisions VMs on Proxmox (1 control plane VM + 1 bare metal worker)
- **Layer 2 (Configuration):** Ansible bootstraps a Talos Kubernetes cluster with Cilium CNI
- **Layer 3 (GitOps):** ArgoCD deploys ~20 Helm-based applications via app-of-apps pattern

Key versions: Talos v1.11.5, Kubernetes v1.34.1, Cilium v1.16.5.

## Common Commands

```bash
# Full deployment (all 3 layers + DNS + CA trust)
make deploy

# Individual layers
make layer1                  # Terraform: create VMs
make layer2                  # Ansible: configure Talos cluster
make layer3                  # Ansible: deploy ArgoCD + apps

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
- `gitops/` — ArgoCD application definitions
  - `app-of-apps.yaml` — Single entry point that auto-discovers all apps in `gitops/apps/`
  - `apps/` — Individual ArgoCD Application YAMLs (one per service)
  - `manifests/` — Kustomize/raw K8s manifests, including SOPS-encrypted secrets
- `scripts/` — `generate-ansible-inventory.py` bridges Terraform outputs to Ansible inventory
- `deploy-homelab.sh` — Master orchestration script (called by `make deploy` and CI)

### Key Design Patterns

**Terraform → Ansible bridge:** Terraform outputs are exported as JSON, then `scripts/generate-ansible-inventory.py` auto-generates Ansible inventory and node vars. Bare metal workers are manually maintained in `ansible/roles/talos-cluster/vars/main.yml` under `baremetal_workers` — the script preserves these entries.

**Talos patches:** Rather than monolithic machine configs, Talos uses patch files in `ansible/roles/talos-cluster/files/` applied during bootstrap: `cni.yaml`, `allowcontrolplanes.yaml`, `kubelet-certs.yaml`, `system-extensions.yaml`, `machine-features.yaml`.

**App-of-apps:** `gitops/app-of-apps.yaml` points to the `gitops/apps/` directory. Adding a new app = creating a new YAML file there. ArgoCD auto-syncs with prune and self-heal enabled.

**Storage:** local-path-provisioner (default StorageClass `local-path`) using dedicated extra disks mounted at `/var/mnt/longhorn` on each node. Simple, zero-maintenance local storage.

**Secrets:** SOPS with age encryption. Rules in `.sops.yaml` — encrypts `*.enc.yaml`, files in `gitops/manifests/secrets/`, and `gitops/manifests/autofix-dojo/*-secret.yaml`. Talos-generated secrets are gitignored.

### Network Layout

| Role | IP(s) |
|------|-------|
| Control plane (VM) | 10.20.0.40 |
| Worker 4 (bare metal) | 10.20.0.45 |
| MetalLB pool | 10.20.0.81-99 |
| Traefik LB / services | 10.20.0.81 |
| k8s-gateway DNS | 10.20.0.82 |

Services are accessible at `*.lab.jamilshaikh.in` (resolved via `/etc/hosts` entries pointing to 10.20.0.81).

## CI/CD

GitHub Actions workflow at `.github/workflows/deploy-homelab.yml` — manual dispatch with `skip_layer1`, `skip_layer2`, `skip_layer3` inputs. Runs on a `self-hosted` runner. Three sequential jobs matching the 3-layer architecture. Layer 2 auto-cleans up VMs on failure.

## Commit Style

```
type(scope): description
```

Examples: `fix(cloudflared): re-enable probes`, `feat(autofix-dojo): add SOPS-encrypted secret`, `chore(helm): critical upgrades`. Main branch is `master`.

## Important Notes

- Talos configs in `talos-homelab-cluster/` are generated and gitignored — never commit them
- Terraform state is managed remotely via Terraform Cloud — `.tfstate` files are gitignored
- The `TALOSCONFIG` path used by Makefile is `/tmp/talos-homelab-cluster/rendered/talosconfig`
- Talos is an immutable OS with no SSH — use `talosctl` for all node interaction
- Version upgrades: update `talos_version` / `kubernetes_version` / `cilium_version` in `ansible/roles/talos-cluster/vars/main.yml`, then re-run Layer 2
- Adding new ArgoCD apps: create a YAML in `gitops/apps/`, it's auto-discovered by app-of-apps
