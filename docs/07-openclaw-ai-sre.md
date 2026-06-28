# BTS: openclaw AI SRE — K8s Deployment

> Started: 2026-06-27 | Status: Done (Steps 1–8 complete)

## What is openclaw?

[openclaw](https://openclaw.dev) is an AI agent platform (npm SaaS package) that runs scheduled and interactive agents via Mattermost and Telegram. We use it as an AI SRE — automated agents that watch the cluster and push notifications without needing a human on-call.

Originally ran on a bare-metal Intel i3 Debian machine (`noon`, `100.123.217.1` Tailscale). Moving it to the cluster eliminates the dependency on that machine and brings it under GitOps.

## Why move to Kubernetes?

| Reason | Detail |
|---|---|
| No special hardware needed | `noon` only ran openclaw + some Docker apps |
| GitOps managed | Deployment, config, secrets all in version control |
| Automatic restarts | Pod restarts on crash, no systemd babysitting |
| Log aggregation | Loki/Promtail picks up pod logs automatically |
| Network access | Pods on `192.168.60.0/24` can reach Talos nodes directly — no SSH tunnels needed |

## Architecture Decision: LLM Model Chain

**Final model chain (as of 2026-06-28):**

```
Primary:    anthropic/claude-haiku-4-5-20251001   (fast, always warm, ~$0.50/month)
Fallback 1: groq/llama-3.3-70b-versatile          (free, ~300 tok/s, OpenAI-compatible)
Fallback 2: cerebras/llama3.1-70b                 (free, ~2000 tok/s — limited to 32k context)
Fallback 3: ollama/qwen2.5:7b                     (in-cluster, $0, CPU-only, slow)
```

**Why Haiku as primary (not Groq/Cerebras)?**

Haiku is loaded via `ANTHROPIC_API_KEY` env var — no warmup needed, always available at pod start. Groq and Cerebras use `openai-completions` provider type which goes through a 5-second startup warmup. On first call, Groq's auth takes ~13 seconds → warmup timeout → session defaults to Haiku anyway. By making Haiku the explicit primary, sessions start instantly and consistently.

Cerebras has a hard 32k context limit that caused compaction loops (context fills up, compaction fails, session stalls). Stays in chain as last cloud fallback before Ollama.

**Why not Sonnet for everything?**
Monitoring crons run every 15-30 minutes. 96 runs/day × Sonnet pricing (~$3/$15 per M tokens) = expensive fast. Haiku handles structured `kubectl` output parsing perfectly at ~12× less cost. Sonnet is reserved for `prospect-hunter` only (once weekly, needs deep reasoning).

**Ollama status:** Kept as offline fallback only. CPU-only inference on a homelab worker is too slow for interactive use (~5 min/response). Useful only if all cloud providers are unreachable simultaneously. A GPU-based worker node would change this.

**Special-purpose overrides:**
- `prospect-hunter` cron: uses `anthropic/claude-sonnet-4-6` explicitly (overrides default)

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
2. `openclaw-config` — openclaw.json with Mattermost/Telegram tokens
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
4. Restarted pod — both `ollama/qwen2.5:7b` and `anthropic/claude-haiku-4-5-20251001` auto-detected, all 6 crons active

## Step 6: Mattermost Migration + Hardening (2026-06-27)

1. Switched OpenClaw channel config template from `channels.slack` (socket mode) to `channels.mattermost` (bot token + base URL).
2. Added Mattermost plugin install in image build (`@openclaw/mattermost`) alongside `openclaw` CLI.
3. Updated secrets runbook to source `MATTERMOST_BOT_TOKEN` from Mattermost Bot Accounts.
4. Applied small pod hardening in deployment: `seccompProfile: RuntimeDefault`, `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`.

## Step 7: Hybrid Remediation (2026-06-28)

Moved from pure monitoring → monitoring + remediation. Two modes running in parallel.

---

### How it works end-to-end

#### Option B — Auto-fix (no approval, fires automatically)

Triggers: Pending pods (scheduling deadlock) and CrashLoopBackOff pods (stuck in backoff).

```
cron fires (every 1h / every 15m)
  └── kubectl get pods -A --no-headers
        └── awk filter: $4=="Pending" or status~CrashLoopBackOff
              ├── nothing found → silent
              └── found →
                    kubectl delete pod <pod> -n <ns> --grace-period=0
                    openclaw message send → Mattermost #devops
                    "🔧 Auto-fixed: deleted Pending pod `x` in `ns` — rescheduling now"
```

**Why this is safe:**
- Pods are ephemeral — deleting a Pending pod just reschedules it, no data loss
- Deleting a CrashLoop pod resets the exponential backoff (5min wait → immediate retry)
- The pod's owner (Deployment/StatefulSet) recreates it automatically

#### Option A — Approval-gated (you reply to trigger)

Triggers: ArgoCD drift, node not Ready, non-CrashLoop pod failures.

```
cron detects issue (e.g. ArgoCD app OutOfSync)
  └── posts to Mattermost #devops:
        "⚠️ ArgoCD drift detected:
         openclaw Unknown Healthy
         Reply `sync openclaw` to force sync"

You reply in #devops or DM openclaw-bot:
  └── "sync openclaw"
        └── openclaw-bot LLM agent picks up message
              └── runs: argocd app sync openclaw
                         OR kubectl rollout restart deployment/x -n y
              └── posts result back to channel
```

**Supported reply commands (chat with bot directly):**
| You say | Bot does |
|---|---|
| `fix <pod> -n <namespace>` | `kubectl delete pod <pod> -n <namespace>` |
| `sync <app-name>` | `argocd app sync <app-name>` |
| `sync all` | syncs all drifted ArgoCD apps |
| `restart deployment <name> -n <ns>` | `kubectl rollout restart deployment/<name> -n <ns>` |
| `status` | full cluster health summary |

You can say these in the **#devops channel** (bot sees mentions) or **DM openclaw-bot** directly.

---

### RBAC changes (`gitops/manifests/openclaw/rbac.yaml`)

| Permission | Scope | Why |
|---|---|---|
| `pods: [delete]` | cluster-wide | Auto-fix Pending/CrashLoop |
| `deployments, daemonsets, statefulsets: [patch, update]` | cluster-wide | Approval-gated rollout restart |
| `applications (argoproj.io): [patch, update]` | cluster-wide | Approval-gated ArgoCD sync |

Read permissions unchanged — bot can still only see, never modify data/secrets.

---

### Where to see the cron job list

**Option 1 — CLI:**
```bash
kubectl exec -n openclaw deployment/openclaw -- openclaw cron list --all
```

**Option 2 — DM the bot in Mattermost:**
```
cron list
```
openclaw-bot replies with all jobs, schedules, last run status.

**Option 3 — Gateway UI (port-forward):**
```bash
kubectl port-forward -n openclaw deployment/openclaw 18789:18789
# open http://localhost:18789 in browser
```

---

### Live cron schedule

| Job | Fires | Behaviour |
|---|---|---|
| `critical-alert-check` | every 15m | Auto-deletes CrashLoop pods; posts others for approval |
| `argocd-sync-check` | every 30m | Posts drift with `sync <app>` approval instruction |
| `cluster-health-check` | every 1h | Auto-deletes Pending pods; posts node issues for approval |
| `talos-health-check` | every 1h | Reports etcd/node health (disabled, re-enable if needed) |
| `prospect-hunter` | Mon 9am IST | Business leads via Claude Sonnet (disabled) |

## Step 8: Model Chain Simplification (2026-06-28)

After testing Groq/Cerebras in production-like runs, the chain was simplified for reliability and predictable cost:

```
Primary:  anthropic/claude-haiku-4-5-20251001
Fallback: ollama/qwen2.5:7b
```

Operational pattern now is:
- Cron monitoring/remediation jobs are command-based where possible (low/no token cost)
- LLM usage is reserved for higher-value summarization/troubleshooting jobs
- Haiku remains default for interactive and analytical turns

## Step 9: Phase 3 — Runbook Intelligence (2026-06-28)

### 3a Incident Correlation (new cron)

- Added `incident-correlator` (every 30m)
- Uses Haiku to correlate issues across pod health + ArgoCD app state
- Posts one unified message only when >=2 related issues are detected
- Output format enforced:
  - `🔗 Correlated incident: ... Affected: ... Suggested action: ...`

### 3b Capacity Forecasting (new cron)

- Added `capacity-forecast` (`0 8 * * 1` @ `Asia/Kolkata`)
- Uses Haiku to summarize:
  - `kubectl top nodes`
  - `kubectl top pods -A`
  - `kubectl get pvc -A`
- Reports node risk as traffic-light status with explicit action line for red conditions

### 3c Automated Postmortems (enhanced existing crons)

Enhanced `cluster-health-check` + `critical-alert-check` command payloads:

- After auto-delete, checks recurrence using namespace events (`reason=Killing`)
- First occurrence:
  - `🔧 Auto-fixed: deleted <pod> in <ns>`
- Recurring occurrence (`>=2/day`):
  - `🔴 Recurring failure: ... needs human review`
- Persists daily namespace counts via annotation:
  - `openclaw.io/autofix-count-<YYYYMMDD>=N`
- Added production safety exclusions in auto-fix path:
  - `paas-system`, `paas-deployments`, `paas-tenant-*`

### 3d Runbook Execution (chat-triggered model)

Runbooks are executed through owner-approved chat commands in Mattermost (DM or `#devops` mention). The service account now has required permissions for node patch/eviction and namespace annotation.

Supported operational commands:

| Trigger | Action |
|---|---|
| `drain <node>` | Cordon + confirmation + drain workflow |
| `sync all apps` | Sync all OutOfSync ArgoCD apps with progress messages |
| `logs <pod> -n <namespace>` | Tail and return latest 50 lines |
| `restart <kind> <name> -n <namespace>` | Rollout restart + completion status |

Owner gate remains mandatory via `commands.ownerAllowFrom` mapping.

### 3e spinup.in PaaS Awareness (new cron)

- Added `paas-health-check` (every 10m)
- Checks and reports only (no auto-remediation in PaaS namespaces):
  - `control-plane` pod in `paas-system`
  - `paas-db` CNPG ready instances
  - stuck build jobs (`>15m`) in `paas-deployments`
  - pod anomalies in `paas-deployments`
  - `registry` pod status in `paas-system`
- Sends additional critical message when `control-plane` or `paas-db` are degraded

## Known Gaps

- **GitHub Actions for image builds:** `.github/workflows/build-openclaw.yml` is committed and auto-triggers on changes to `gitops/manifests/openclaw/`. Uses `GHCR_TOKEN` secret if set, falls back to `GITHUB_TOKEN`.

## Client Onboarding

- Mattermost desktop + iPhone setup guide: `docs/mattermost-client-setup.md`

---

## Cron Job Reference

| Job | Schedule | Model | Mattermost Channel | Purpose |
|---|---|---|---|---|
| `cluster-health-check` | every 1h | command (no model) | `#devops` | Pending pod auto-fix + recurring postmortem |
| `critical-alert-check` | every 15m | command (no model) | `#devops` | CrashLoop auto-fix + critical issue reporting |
| `argocd-sync-check` | every 30m | command (no model) | `#devops` | Drift detection alerting |
| `incident-correlator` | every 30m | `claude-haiku-4-5-20251001` | `#devops` | Correlated multi-signal incident summary |
| `capacity-forecast` | Mon 8:00 IST | `claude-haiku-4-5-20251001` | `#devops` | Weekly CPU/memory/PVC risk forecast |
| `paas-health-check` | every 10m | command (no model) | `#devops` | spinup.in PaaS health (report-only) |
| `talos-health-check` | every 1h | `ollama/qwen2.5:7b` | `#devops` | etcd + Talos node diagnostics (disabled) |
| `prospect-hunter` | Mon 9:00 IST | `claude-sonnet-4-6` | `#business` | Business lead generation (disabled) |
