# BTS: kagent — Cluster-Native AI Agents

> Started: 2026-07-09 | Status: Done

## What is kagent?

[kagent](https://github.com/kagent-dev/kagent) is a Kubernetes-native framework (CNCF sandbox) for running AI agents as cluster resources — Agents, ModelConfigs, and ToolServers are all CRDs, reconciled by a controller the same way any other Kubernetes object is. It ships with pre-built MCP tool servers for Kubernetes, Helm, Cilium, PromQL, and Grafana.

**Repo:** `gitops/apps/kagent-crds.yaml` + `gitops/apps/kagent.yaml`
**UI:** https://kagent.jamilshaikh.in
**Chart source:** OCI, `ghcr.io/kagent-dev/kagent/helm`, v0.9.11

## Why kagent alongside openclaw?

openclaw is the conversational front-end (Mattermost chatbot, cron-based monitoring/remediation). kagent adds structured, per-domain specialist agents with proper tool-call tracing — something openclaw's shell-script crons don't give visibility into. They run side by side, not as a replacement for each other. See [Known Gaps](#known-gaps) below for the (currently manual) bridge between the two.

## Architecture Decisions

### Trimmed agent set

The chart enables 13 tool-agent pods by default. Three were disabled — `istio-agent`, `kgateway-agent`, `argo-rollouts-agent` — since this cluster runs Traefik + Cloudflare Tunnel (not Istio/kgateway) and plain ArgoCD (not Argo Rollouts). Kept: `k8s-agent`, `helm-agent`, `cilium-manager-agent`, `cilium-policy-agent`, `cilium-debug-agent`, `promql-agent`, `observability-agent`, `grafana-mcp`, `querydoc`.

Live footprint per agent pod is tiny in practice — a few mCPU, ~190Mi memory each — well under the chart's own resource *requests*, but worker CPU *requests* still jumped from 52% to 72% after adding all of these. Worth revisiting if more workloads get added later.

### LLM provider: DeepSeek via the OpenAI-compatible endpoint

No DeepSeek preset exists in the chart's `providers` values block. Used the generic `openAI` provider with a `config.baseUrl` override pointing at `https://api.deepseek.com` — same pattern as openclaw, same underlying `DEEPSEEK_API_KEY`, duplicated into a `kagent-tokens` secret (separate secret per app, same key value).

```yaml
providers:
  default: openAI
  openAI:
    provider: OpenAI
    model: "deepseek-chat"
    apiKeySecretRef: kagent-tokens
    apiKeySecretKey: DEEPSEEK_API_KEY
    config:
      baseUrl: "https://api.deepseek.com"
```

### OCI Helm source gotcha

ArgoCD's `source.chart` + `source.repoURL` combo (unregistered OCI repo) hit a resolver bug — the chart name never got appended to the digest-lookup request, producing `403: denied` against ghcr.io regardless of correct values. Fixed by pre-registering the OCI registry as an ArgoCD `Repository` Secret (`enableOCI: "true"`, no credentials needed — public registry) via `gitops/manifests/argocd-config/kagent-oci-repo.yaml`, then dropping `oci://` from `repoURL` to match the registered repo's `url` field exactly.

### Grafana MCP: wrong default URL + Host header rejection

Two separate bugs, both required fixing before `grafana-mcp` worked:

1. Chart default (`grafana.kagent:3000`) doesn't exist on this cluster — Grafana is the `victoria-metrics-grafana` subchart in `monitoring`, not a `kagent`-namespace service. Fixed via `grafana-mcp.grafana.url` override.
2. The `mcp/grafana` image's `-allowed-hosts` flag defaults to loopback-only, rejecting every in-cluster caller — `kagent-controller` connects via the Kubernetes Service DNS name (`kagent-grafana-mcp.kagent:8000`), not `localhost`, so every reconcile attempt failed with `403 forbidden: host not allowed`. Fixed via an explicit `-allowed-hosts` arg listing both the short and FQDN service names.

Grafana's own service account token (Viewer role, `kagent-mcp` SA) is stored as `grafana-mcp-token`, created manually since Grafana's admin credentials had drifted from the k8s Secret that originally seeded them (someone changed the admin password via the UI at some point — the Secret still had the stale original value).

## Access Control

kagent's Helm chart ships with `controller.auth.mode: unsecure` and `oauth2-proxy.enabled: false` by default — **zero login of its own**, and the underlying `kagent-tools` ServiceAccount is bound to a literal cluster-admin `ClusterRole` (`apiGroups: ['*'], resources: ['*'], verbs: ['*']`). This was live and internet-reachable for roughly an hour before being caught and fixed.

See [Access Control & SSO](./09-access-control-sso.md) for the full Cloudflare Access setup that now gates it — kagent was the first of three apps (`kagent`, `grafana`, `argocd`) to get this treatment the same night.

**Still open, not yet done:** the `kagent-tools` cluster-admin RBAC itself hasn't been scoped down. Cloudflare Access controls *who* can reach the UI, not what the agents are authorized to do once inside.

## Known Gaps

- **No openclaw ↔ kagent bridge.** Discussed three options (use both separately / point openclaw's remediation cron at a kagent agent over A2A / write a proper openclaw plugin) — went with "use both separately" for now. kagent's agents speak the standard [A2A protocol](https://a2a-protocol.org), confirmed via each pod's `.well-known/agent-card.json` — the A2A route is the more promising follow-up if this becomes worth doing properly.
- Setup wizard (first Agent creation) was in progress at the end of this session — pointed at `k8s-agent`, `helm-agent`, `cilium-manager-agent`, `cilium-policy-agent`, `promql-agent`, `grafana-mcp` as the initial tool set, with a Talos-specific system prompt addition (no `kubectl exec`/SSH onto nodes — Talos has none).
