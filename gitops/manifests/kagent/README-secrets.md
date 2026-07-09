# kagent — Secret Setup (one-time, run before/after ArgoCD syncs)

Not in git. The `kagent` namespace is created by the `kagent-crds`/`kagent`
Applications (CreateNamespace=true) — create this secret any time after that,
before agents will actually respond (LLM calls will fail without it).

## kagent-tokens (DeepSeek API key, reused from openclaw)

```bash
kubectl create secret generic kagent-tokens -n kagent \
  --from-literal=DEEPSEEK_API_KEY='sk-...'
```

To rotate:

```bash
kubectl create secret generic kagent-tokens -n kagent \
  --from-literal=DEEPSEEK_API_KEY='sk-...' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/kagent-controller -n kagent
```

## grafana-mcp-token (Grafana service account token)

Grafana → Administration → Service accounts → New (role: Viewer) → Add
service account token. Grafana's admin credentials can drift from the
`victoria-metrics-grafana` k8s Secret if changed via the UI, so this has to
be done manually rather than scripted against that secret.

```bash
kubectl create secret generic grafana-mcp-token -n kagent \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='glsa_...'
```

## kagent-basic-auth (Traefik BasicAuth — required, not optional)

**kagent's UI ships with `controller.auth.mode: unsecure` and no oauth2-proxy
by default — the chart has zero built-in login.** The IngressRoute
(`kagent-ingressroute.yaml`) attaches a `kagent-basic-auth` Traefik
Middleware; without this secret existing, that Middleware has nothing to
read and Traefik will reject all requests (fail-closed, not fail-open —
safe default, but means this secret must exist before the ingress works
at all).

```bash
htpasswd -nbB admin 'your-password-here' > /tmp/kagent-htpasswd
kubectl create secret generic kagent-basic-auth -n kagent \
  --from-file=users=/tmp/kagent-htpasswd
rm /tmp/kagent-htpasswd
```

Treat this as a stopgap, not the long-term answer — the underlying
`kagent-tools` ServiceAccount is bound to a literal cluster-admin
ClusterRole (`apiGroups: ['*'], resources: ['*'], verbs: ['*']`), so
anyone who gets past this Basic Auth has full cluster access. Proper
fix is `controller.auth.mode: trusted-proxy` + `oauth2-proxy.enabled: true`
with a real OIDC provider — tracked as a follow-up, not yet done.

## Notes

- `gitops/apps/kagent.yaml` sets `providers.openAI.config.baseUrl` to
  DeepSeek's OpenAI-compatible endpoint — same provider mechanism as
  openclaw, different tool.
- After the `kagent`/`kagent-crds` apps first create the `kagent` namespace,
  the `ingress-routes` app (sync-wave 4, runs *before* kagent's wave 6/7)
  may need a manual hard-refresh in ArgoCD once the namespace exists —
  same one-time gotcha hit when Coder was added.
