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

## Access control — Cloudflare Access (not Kubernetes-side)

**kagent's UI ships with `controller.auth.mode: unsecure` and no oauth2-proxy
by default — the chart has zero built-in login of its own.** Rather than
running an in-cluster auth proxy, access is gated at Cloudflare's edge,
*before* traffic ever reaches the tunnel:

- Access Application `kagent` (Cloudflare account `2526e7c2985b2dde30ed8f5018553908`),
  scoped only to `kagent.jamilshaikh.in` — not the whole domain.
- Identity provider: GitHub OAuth (Zero Trust team `jamilhomelab`,
  callback `https://jamilhomelab.cloudflareaccess.com/cdn-cgi/access/callback`).
- Policy `allow-jamil`: requires GitHub login **and** email
  `jamilshaikh07@gmail.com` — `github-organization` policy rules only work
  for GitHub orgs, not personal accounts, hence `login_method` + `email`.
- None of this is in git — Access Apps/Policies/IdPs live in Cloudflare,
  not Kubernetes. If rebuilding from scratch, redo this via the Cloudflare
  dashboard or API (Access: Apps and Policies + Access: Identity Providers
  permissions needed on the API token).

An earlier stopgap (Traefik BasicAuth middleware) was used for about an
hour before this was wired up — removed once Access was confirmed
enforcing (`curl -I` returns a 302 to the Cloudflare login page).

Same GitHub IdP + `allow-jamil`-style policy was also applied to two more
scoped Access Applications, same "not in git, redo via Cloudflare
dashboard/API on rebuild" caveat applying to all three:

- `grafana.jamilshaikh.in` (app id `89d2c1ad-99ee-45b0-a44b-2fa38985b499`)
  — Grafana's own local admin login stays underneath as a second layer,
  this isn't a replacement for it.
- `argocd.jamilshaikh.in` (app id `7f54e53c-53f2-48df-b324-a942ca64f993`)
  — unlike Grafana, ArgoCD's *own* login was also replaced with GitHub SSO
  (Dex connector, separate GitHub OAuth App from the Cloudflare Access one)
  the same night — see `gitops/manifests/argocd-config/README-sso.md`.
  Logging in via GitHub now grants `role:admin` directly, same rights as
  the local `admin` account.

Note: once you've authenticated via GitHub for *any* Access-protected
`*.jamilshaikh.in` app in a browser, Cloudflare Access silently reuses
that session for the others in the same browser — you won't see a second
GitHub prompt, it just passes you straight through to each app's own
(separate, unrelated) login.

Still worth doing eventually: the underlying `kagent-tools` ServiceAccount
is bound to a literal cluster-admin ClusterRole (`apiGroups: ['*'],
resources: ['*'], verbs: ['*']`) — Access controls *who* can reach the UI,
not what the agents themselves are allowed to do once inside. Scoping that
RBAC down is a separate, not-yet-done follow-up.

## Notes

- `gitops/apps/kagent.yaml` sets `providers.openAI.config.baseUrl` to
  DeepSeek's OpenAI-compatible endpoint — same provider mechanism as
  openclaw, different tool.
- After the `kagent`/`kagent-crds` apps first create the `kagent` namespace,
  the `ingress-routes` app (sync-wave 4, runs *before* kagent's wave 6/7)
  may need a manual hard-refresh in ArgoCD once the namespace exists —
  same one-time gotcha hit when Coder was added.
