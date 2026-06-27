# BTS: openclaw AI SRE — K8s Deployment

> Started: 2026-06-27 | Status: Done (Steps 1–4 complete)

## What is openclaw?

[openclaw](https://openclaw.dev) is an AI agent platform (npm SaaS package) that runs scheduled and interactive agents via Slack and Telegram. We use it as an AI SRE — automated agents that watch the cluster and push notifications without needing a human on-call.

Originally ran on a bare-metal Intel i3 Debian machine (`noon`, `100.123.217.1` Tailscale). Moving it to the cluster eliminates the dependency on that machine and brings it under GitOps.

## Why move to Kubernetes?

| Reason | Detail |
|---|---|
| No special hardware needed | `noon` only ran openclaw + some Docker apps |
| GitOps managed | Deployment, config, secrets all in version control |
| Automatic restarts | Pod restarts on crash, no systemd babysitting |
| Log aggregation | Loki/Promtail picks up pod logs automatically |
| Network access | Pods on `192.168.60.0/24` can reach Talos nodes directly — no SSH tunnels needed |

## Architecture Decision: LLM Tier Split

The biggest cost decision — which model for which job:

```
Monitoring crons (cluster-health, alerts, talos, argocd)
  → ollama/qwen2.5:7b  — runs IN the cluster, $0, private
  → Tool calling works natively, 128k context

News digests (daily-ai-news, tech-news-digest)
  → anthropic/claude-haiku-4-5  — cloud, ~$0.50/month

Prospect hunter (family business leads, weekly)
  → anthropic/claude-sonnet-4-6  — cloud, ~$0.20/week
```

**Why not Gemini free tier (the old setup)?**
Gemini free tier worked but adds an external cloud dependency for monitoring. Ollama is self-contained — if the internet is down the cluster still gets watched.

**Why not Claude for everything?**
Monitoring crons run every 15-30 minutes. 96 runs/day × Sonnet pricing = expensive fast. Ollama handles structured kubectl output parsing perfectly at $0.

**Why qwen2.5:7b specifically?**
- Reliable tool calling (monitoring agents need to exec kubectl/talosctl)
- 4.7GB model weight — fits comfortably on worker node (9GB free RAM)
- 128k context window (openclaw requires 64k minimum for agentic loops)
- Fast enough on CPU for non-realtime crons (30-60s per run is fine)

## Step 1: Ollama on Kubernetes

### What we built

- `ollama` namespace
- Deployment pinned to `talos-wk-01` (worker node has the free RAM)
- 20Gi PVC for model storage at `/root/.ollama`
- ClusterIP Service on port `11434`
- ArgoCD app auto-syncing from `gitops/apps/ollama.yaml`

### Why pin to worker?

Control plane (`talos-cp-01`) is at 78% memory — kube-apiserver alone eats 2.8GB. Worker has ~9GB free. Ollama model weights live in memory while serving — we don't want to starve the control plane.

### Model pull strategy

First startup pulls `qwen2.5:7b` via a `postStart` lifecycle hook. The 4.7GB download happens once; subsequent restarts load from the PVC. Pull can take 5-10 min on first deploy.

### Resource limits

```yaml
resources:
  requests:
    cpu: 500m
    memory: 6Gi
  limits:
    cpu: 4
    memory: 8Gi
```

No GPU on these VMs — CPU inference only. 4 CPU limit prevents Ollama from starving other workloads during a cron burst.

---

## Step 2: openclaw Container Image

> Status: Done — `ghcr.io/jamilshaikh07/openclaw-sre:latest`

Base: `node:22-slim` (openclaw requires Node ≥22.19.0). Tools installed at build time:
- `kubectl v1.34.1` — matches cluster version
- `talosctl v1.12.6` — matches Talos version
- `openclaw@latest` — npm install -g

Runs as the built-in `node` user (uid 1000). Built and pushed manually to GHCR with `write:packages` scope. A GitHub Actions workflow file exists in the repo but needs the `workflow` token scope to auto-trigger — add via `gh auth refresh -s workflow` when ready.

**Why not `registry.spinup.in`?** That registry uses bcrypt htpasswd auth — we had the hash but not the plaintext password to `docker login`. GHCR worked cleanly with the existing gh token.

---

## Step 3: openclaw Deployment

> Status: Done

Key design decisions:

**In-cluster kubectl auth:** No kubeconfig mounted. Pod uses its ServiceAccount token (`/var/run/secrets/kubernetes.io/serviceaccount/`) — kubectl auto-detects it via `KUBERNETES_SERVICE_HOST`. Cleaner than mounting an external kubeconfig that can go stale.

**talosctl:** Needs a talosconfig file (cluster CA + endpoints). Mounted from `openclaw-talosconfig` Secret at `/home/node/.talos/config`. The talosconfig is gitignored (contains cluster CA) — recreated from `talos-homelab-cluster/rendered/talosconfig` on rebuild.

**Config seeding:** openclaw.json (with Ollama provider, channel tokens) is stored in a Secret (`openclaw-config`). An init container copies it to the PVC on first boot, then leaves it alone on subsequent starts — so live config changes on the PVC survive pod restarts.

**Secrets required before first deploy (see `README-secrets.md`):**
1. `openclaw-tokens` — ANTHROPIC_API_KEY + GEMINI_API_KEY
2. `openclaw-config` — openclaw.json with Slack/Telegram tokens
3. `openclaw-talosconfig` — already created by `make deploy`

**RBAC:** ClusterRole `openclaw-readonly` — get/list/watch on pods, nodes, events, deployments, statefulsets, daemonsets, ArgoCD applications, metrics. No write permissions anywhere.

---

## Step 4: Cron Model Routing

> Status: Done

Migrated `jobs.json` from noon machine, applied these changes:

| Job | Change |
|---|---|
| `cluster-health-check` | model → `ollama/qwen2.5:7b`, IPs updated to `192.168.60.40/41`, enabled |
| `critical-alert-check` | model → `ollama/qwen2.5:7b`, enabled |
| `talos-health-check` | model → `ollama/qwen2.5:7b`, IPs: `192.168.60.40/41`, `talos-wk-04` → `talos-wk-01`, enabled |
| `argocd-sync-check` | model → `ollama/qwen2.5:7b`, enabled |
| `tech-news-digest` | model → `anthropic/claude-haiku-4-5-20251001`, prompt rewritten to inline Node.js RSS fetch (no Python dependency) |
| `prospect-hunter` | model → `anthropic/claude-sonnet-4-6`, initially disabled pending API key |

The `jobs.json` was injected via `kubectl cp` to the live pod's PVC. On next restart, openclaw auto-migrated it from JSON to SQLite at `~/.openclaw/state/openclaw.sqlite` and renamed the original to `jobs.json.migrated`.

**SQLite WAL gotcha:** The cron_jobs data landed in the WAL (Write-Ahead Log), not the main DB file. Direct `kubectl cp` of `openclaw.sqlite` returned an empty `cron_jobs` table until the WAL was checkpointed. Fix: copy all three files (`openclaw.sqlite`, `.sqlite-shm`, `.sqlite-wal`), checkpoint locally with `PRAGMA wal_checkpoint(FULL)`, edit, copy back.

**Noon machine cleanup:** The `openclaw-gateway.service` user systemd service on `noon` (`100.123.217.1`) was confirmed stopped before migration to avoid Telegram polling conflicts.

## Step 5: Anthropic API Key + Full Activation (2026-06-27)

1. Created Anthropic API key at console.anthropic.com (spending cap set), wrote to `/tmp/ant-key`
2. Updated `openclaw-tokens` Secret preserving existing `GEMINI_API_KEY`:
   ```bash
   kubectl create secret generic openclaw-tokens -n openclaw \
     --from-literal=ANTHROPIC_API_KEY=$(cat /tmp/ant-key) \
     --from-literal=GEMINI_API_KEY=<existing> \
     --dry-run=client -o yaml | kubectl apply -f -
   shred -u /tmp/ant-key
   ```
3. Re-enabled `prospect-hunter` in SQLite: copied WAL-checkpointed DB, set `enabled=1`, copied back
4. Restarted pod — both `ollama/qwen2.5:7b` and `anthropic/claude-haiku-4-5-20251001` auto-detected, Telegram up, all 6 crons active

## Known Gaps

- **Slack not connecting:** `channels.slack` shows `mode: socket` and valid tokens, but no Slack startup log entries. Likely the Slack app-level token (`xapp-...`) has expired or the Socket Mode configuration changed. Investigate via Slack App settings → Socket Mode. Telegram is working fine in the meantime.
- **GitHub Actions for image builds:** `.github/workflows/build-openclaw.yml` exists locally (untracked). Needs `workflow` token scope: `gh auth refresh -s workflow`. Until then, build and push manually.
- **PodSecurity warnings:** `allowPrivilegeEscalation != false`, `capabilities.drop != ALL`, `runAsNonRoot != true`. Not blocking (warnings only) — address in a future hardening pass.

---

## Cron Job Reference

| Job | Schedule | Model | Slack Channel | Purpose |
|---|---|---|---|---|
| `cluster-health-check` | every 15m | `ollama/qwen2.5:7b` | `#devops` | Node + pod health, resource usage |
| `critical-alert-check` | every 30m | `ollama/qwen2.5:7b` | `#alerts` | CrashLoop, OOMKill, node NotReady |
| `talos-health-check` | every 1h | `ollama/qwen2.5:7b` | `#devops` | etcd, node memory/disk |
| `argocd-sync-check` | every 30m | `ollama/qwen2.5:7b` | `#devops` | App sync drift |
| `tech-news-digest` | 8:10 AM IST | `claude-haiku-4-5-20251001` | Telegram DM | K8s/DevOps/AI digest (inline Node.js RSS) |
| `prospect-hunter` | Mon 9:00 AM IST | `claude-sonnet-4-6` | `#business` | Maharashtra pharma/chemical leads |
