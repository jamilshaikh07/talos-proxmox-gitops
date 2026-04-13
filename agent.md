# Agent

## Purpose
This repository automates a Talos Kubernetes homelab on Proxmox using a 3-layer model:
1. Terraform for VM infrastructure.
2. Ansible for Talos and cluster bootstrap.
3. GitOps for application delivery.

This agent document defines how to operate safely, predictably, and with minimal downtime.

## Operating Principles
- Prefer additive, reversible changes.
- Plan before apply for infrastructure changes.
- Never destroy infrastructure unless explicitly requested.
- Keep Terraform as source of truth for Talos VM topology.
- Regenerate inventory after Terraform changes.
- Validate after each significant change.

## Guardrails
- Do not force destructive git actions.
- Treat local-path storage as node-bound and non-replicated.
- Drain workers before scale-down.
- Keep OPNsense DHCP reservations in sync with planned MAC/IP output.
- Assume the environment is long-lived, not ephemeral.

## Standard Workflows
### Full Deploy
1. make deploy

### Infra Change Only
1. make terraform-plan
2. make layer1
3. make sync-inventory

### Talos Reconcile
1. make layer2

### GitOps Reconcile
1. make layer3

### Scale or Resize
1. make scale-plan WORKER_COUNT=<n> WORKER_MEMORY=<mb> WORKER_CORES=<n>
2. make scale-apply WORKER_COUNT=<n> WORKER_MEMORY=<mb> WORKER_CORES=<n>
3. make planned-dhcp
4. make layer2

### Safe Scale-Down
1. make drain-node NODE=<worker-name>
2. make scale-apply WORKER_COUNT=<smaller-n>
3. make layer2

## Validation Checklist
- terraform validate (terraform/proxmox-homelab)
- ansible-playbook --syntax-check for touched playbooks
- kubectl get nodes
- make status-apps

## Next Reliability Focus
- Add Cloudflare Access in front of public services.
- Move Grafana and ArgoCD auth to OIDC.
- Add periodic backup/restore verification for critical app data.
