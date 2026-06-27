# openclaw Architecture

```mermaid
flowchart TB
    subgraph ext ["External"]
        GH["GitHub\ntalos-proxmox-gitops"]
        GHCR["GHCR\nopenclaw-sre:latest"]
        ANT["Anthropic API\nhaiku-4-5 · sonnet-4-6"]
        MM["Mattermost\nhttps://mattermost.jamilshaikh.in\n#devops #alerts #business #news"]
    end

    subgraph cluster ["Talos K8s Cluster · 192.168.60.0/24"]
        ARGO["ArgoCD\ngitops/apps/openclaw.yaml"]

        subgraph ocns ["namespace: openclaw"]
            OC["openclaw pod\n(talos-wk-01)\nopenclaw gateway :18789"]
            PVC["PVC: openclaw-data 2Gi\n~/.openclaw/openclaw.json\n~/.openclaw/state/openclaw.sqlite"]
            SEC_CFG["Secret: openclaw-config\nopenclaw.json  ← tokens + channels"]
            SEC_TOK["Secret: openclaw-tokens\nANTHROPIC_API_KEY"]
            SEC_TAL["Secret: openclaw-talosconfig\nconfig"]
        end

        subgraph ollns ["namespace: ollama"]
            OLL["Ollama pod\n(talos-wk-01)\nqwen2.5:7b · CPU inference"]
            OLLPVC["PVC: ollama-models 20Gi"]
        end

        subgraph nodes ["Talos Nodes"]
            CP["talos-cp-01\n192.168.60.40"]
            WK["talos-wk-01\n192.168.60.41"]
        end

        SA["ServiceAccount: openclaw\nClusterRole: openclaw-readonly"]
    end

    GH -->|"git sync (ArgoCD)"| ARGO
    ARGO -->|"manages manifests"| OC
    GHCR -->|"imagePull (public)"| OC

    SEC_CFG -->|"init container seeds on first boot"| PVC
    SEC_TOK --> OC
    SEC_TAL --> OC
    SA --> OC
    OC <--> PVC

    OC -->|"monitoring crons\ncluster-health · critical-alert\ntalos-health · argocd-sync\nollama/qwen2.5:7b"| OLL
    OLL --- OLLPVC

    OC -->|"tech-news-digest (daily 8:10 IST)\nprospect-hunter (Mon 9 IST)\nanthropic/claude-haiku/sonnet"| ANT

    OC -->|"kubectl / SA token"| CP
    OC -->|"kubectl + talosctl"| WK

    OC -->|"Mattermost Bot API\n(bot token + baseUrl)\nalerts + health reports + digest"| MM
```

## Cron → Model Routing

| Cron | Schedule | Model | Delivery |
|---|---|---|---|
| cluster-health-check | every 15m | `ollama/qwen2.5:7b` | Mattermost #devops |
| critical-alert-check | every 30m | `ollama/qwen2.5:7b` | Mattermost #alerts (silent if OK) |
| talos-health-check | every 1h | `ollama/qwen2.5:7b` | Mattermost #devops |
| argocd-sync-check | every 30m | `ollama/qwen2.5:7b` | Mattermost #devops |
| tech-news-digest | daily 8:10 IST | `anthropic/claude-haiku-4-5-20251001` | Mattermost #news |
| prospect-hunter | Mon 9:00 IST | `anthropic/claude-sonnet-4-6` | Mattermost #business |

## Secret Inventory (imperative — never in git)

| Secret | Namespace | Contents |
|---|---|---|
| `openclaw-config` | openclaw | Full `openclaw.json` — gateway token, Mattermost token, model config |
| `openclaw-tokens` | openclaw | `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` |
| `openclaw-talosconfig` | openclaw | `talosconfig` file for talosctl |

Local copies with real values → `secrets/openclaw/` (gitignored).
