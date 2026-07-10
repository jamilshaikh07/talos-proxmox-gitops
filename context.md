# Context

## Repository

- Name: talos-proxmox-gitops
- Branch: master
- Model: production homelab running live workloads (spinup.in, openclaw, bpl-prod, Mattermost)

## Infrastructure Snapshot (Jul 2026)

- Proxmox node: alif (remote, friend's office — access via Tailscale)
- Tailscale IP: 100.127.198.7
- VMs running: talos-cp-01, talos-wk-01, opnsense (VM 102, router)
- talos-cp-01 / talos-wk-01: 4 vCPU / 4 vCPU each (rebalanced 2026-07-09, was 2/6 — CP was the bottleneck at 62% CPU requests on 2 cores)
- OPNsense: WAN on vmbr0 (office LAN DHCP), LAN on vmbr2 (192.168.60.1/24)
- TrueNAS: home LAN (10.20.0.45), Tailscale (100.124.83.72) — backup target only

## Access Pattern

All cluster access requires Tailscale active, then:

```bash
make tunnel   # SSH port-forward localhost:16443 → 192.168.60.40:6443 via prox alias
kubectl ...
make tunnel-stop
```

## Architecture

- Layer 1: Terraform → Proxmox VMs (talos-cp-01, talos-wk-01)
- Layer 2: Ansible → Talos bootstrap + Cilium v1.16.5
- Layer 3: ArgoCD app-of-apps → 29 apps in `gitops/apps/`
- Layer 3a: FluxCD side-by-side (metrics-server, select workloads in `gitops/flux/apps/`)

**GitOps rule:** No manual `kubectl apply` on anything in `gitops/`. All changes go git → push → ArgoCD. Exceptions: imperative secrets and openclaw cron SQLite edits.

## Live Products on This Cluster

| Product | Namespace | Notes |
|---|---|---|
| spinup.in PaaS | paas-system / paas-deployments / paas-tenant-* | NEVER touch paas-* — self-healing |
| KubeWise | kubewise | K8s cost advisor, ArgoCD managed |
| openclaw AI SRE | openclaw | Phase 1–3 cron agent, Mattermost delivery |
| kagent | kagent | Cluster-native AI agents (k8s/helm/cilium/promql/grafana), DeepSeek via OpenAI-compatible provider. See [docs/08-kagent-ai-agents.md](./docs/08-kagent-ai-agents.md) |
| BPL prod | bpl-prod | Production app |
| Mattermost | mattermost | Team chat, openclaw bot target |
| Coder | coder | Self-hosted dev environments (CNPG-backed) |

## Access Control (added 2026-07-09)

Cloudflare Access (GitHub SSO) gates `kagent.jamilshaikh.in`, `grafana.jamilshaikh.in`, `argocd.jamilshaikh.in` — each a separately scoped Access Application, not a domain wildcard. ArgoCD additionally has native GitHub SSO via Dex (replaces the local admin login). None of the Cloudflare-side config is in git. Full details + a real RBAC subject-matching gotcha: [docs/09-access-control-sso.md](./docs/09-access-control-sso.md).

## openclaw AI SRE (Phase 1–3)

All crons run against Haiku (`anthropic/claude-haiku-4-5-20251001`), post to Mattermost `#devops`.

| Phase | What |
|---|---|
| 1 | Monitoring crons: cluster, PaaS, BPL, ArgoCD |
| 2 | Remediation: auto-delete CrashLoop pods, approval-gated sync/rollout |
| 3 | Runbook Intelligence: incident correlation, capacity forecasting, postmortems, drain/sync runbooks |

Config lives on PVC (`openclaw.json`). Hot-reload on file change — no pod restart needed for model config.

## Removed (June 2026 cleanup)

- bpl-stage — removed, only bpl-prod remains
- metrics-server — removed from ArgoCD (use `kubectl top` sparingly)
- Ollama — removed from cluster (local LLM not viable on this hardware)
- Groq / Cerebras — removed from openclaw config (TPM limits + context limits)
- test-pg, pnl-postgres, homelab-postgres DR clusters — removed
- tailscale namespace (operator) — removed
- etcd-backup cron — removed

## Out-of-Band Components

| Component | Notes |
|---|---|
| Velero | Not in ArgoCD. BSL → `http://192.168.60.2:9900` (socat proxy → TrueNAS Tailscale). Daily cron at 02:30 UTC |
| minio-proxy.service | Systemd on Proxmox. `socat 192.168.60.2:9900 → 100.124.83.72:9900`. Restart: `ssh prox systemctl restart minio-proxy` |
| spinup.in control-plane | Self-healing: push to vercel-clone main → redeploys in ~3 min |

## Flux Status

Flux runs side-by-side with ArgoCD. Kustomization `oee-sites-pnl` is **suspended** — managed pnl-postgres and homelab-postgres which were removed. Do not resume.

## Operational Constraints

- local-path storage is node-local — no replication. Scale-down can cause data loss if workloads are pinned to removed nodes.
- Talos has no SSH — all node interaction via `talosctl`.
- DHCP reservations are MAC-based via OPNsense — static for cp (192.168.60.40) and worker (192.168.60.41).
- Terraform state is remote (Terraform Cloud workspace: alif) — no `.tfstate` in git.
