# Context

## Repository
- Name: talos-proxmox-gitops
- Branch: master
- Model: long-running homelab infrastructure, not short-lived test infra

## Current Infrastructure Snapshot
- Proxmox node: alif
- CPU: 8 cores
- Memory: 31.25 GiB total, approximately 23.69 GiB used
- Storage:
  - local: approximately 10.92 GiB used of 93.93 GiB
  - local-lvm: approximately 66.45 GiB used of 348.82 GiB
- VMs running:
  - talos-cp-01
  - talos-wk-01
  - opnsense

## Access Pattern
- Cluster access is tunneled through Proxmox over SSH.
- Primary path:
  - make tunnel
  - kubectl ...
  - make tunnel-stop

## Architecture
- Layer 1: Terraform creates Talos VMs.
- Layer 2: Ansible bootstraps Talos Kubernetes + Cilium.
- Layer 3: ArgoCD app-of-apps deploys platform workloads.
- Layer 3a: Flux side-by-side for selected workloads.

## Recent Changes
- Added Terraform-driven scaling variables and worker count controls.
- Added deterministic planned DHCP reservation output for Talos nodes.
- Added scaling helper targets in Makefile:
  - scale-plan
  - scale-apply
  - planned-dhcp
  - drain-node
  - uncordon-node
  - help-when
- Added scenario runbook docs in README.
- Added label helper playbook: ansible/playbooks/label-nodes.yml

## Operational Constraints
- local-path storage is node-local.
- Scale-down can cause data loss if workloads are still pinned to removed nodes.
- DHCP reservations must match planned MAC/IP data for predictable node addressing.

## Pending Hardening Work
- Cloudflare Access policies for public endpoints.
- OIDC for Grafana.
- OIDC for ArgoCD.
