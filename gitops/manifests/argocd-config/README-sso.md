# ArgoCD GitHub SSO — Setup (not covered by `make layer3` / fresh installs)

Applied live via `helm upgrade` on 2026-07-09, not through the ansible
`gitops-deploy` role or a gitops-managed manifest — `argocd-cm`/
`argocd-rbac-cm` are Helm-owned, and adding a second gitops-managed owner
for them would recreate the exact dual-ownership bug hit earlier the same
night with `argocd-cmd-params-cm` (`server.insecure` flapping between
Helm's `false` default and a gitops override). Redo this the same way on
a rebuild:

## 1. GitHub OAuth App

github.com → Settings → Developer settings → OAuth Apps → New OAuth App
(separate app from the one used for Cloudflare Access — different
callback path):

- Homepage URL: `https://argocd.jamilshaikh.in`
- Authorization callback URL: `https://argocd.jamilshaikh.in/api/dex/callback`

## 2. Store the client secret (imperative, not in git)

```bash
kubectl patch secret argocd-secret -n argocd --type merge \
  -p '{"stringData":{"dex.github.clientSecret":"<client-secret>"}}'
```

## 3. helm upgrade with the Dex connector + RBAC + insecure fix

Dump current live values first (`helm get values argocd -n argocd -a -o yaml`)
rather than using `--set`/`--reuse-values` — this chart has known bugs with
both (`redis.networkPolicy.create` nil pointer, `global.deploymentLabels`
deepCopy panic) that only a full `-f` values file sidesteps. Add to the
dumped file:

```yaml
configs:
  cm:
    url: https://argocd.jamilshaikh.in
    dex.config: |
      connectors:
        - type: github
          id: github
          name: GitHub
          config:
            clientID: <client-id-from-step-1>
            clientSecret: $dex.github.clientSecret
  params:
    server.insecure: true   # NOT false — see argocd-cmd-params-cm dual-ownership note below
  rbac:
    policy.csv: |
      g, jamilshaikh07, role:admin
```

Then:

```bash
helm upgrade argocd argo/argo-cd -n argocd --version <current-chart-version> -f values.yaml
```

Restarts `argocd-dex-server` + `argocd-server` (~30s blip, single replica
each, no HA — same as every other live ArgoCD change this repo has made).

## Why `server.insecure: true` has to be in here too

`configs.params.server.insecure` in the Helm chart's own values defaults to
`false`, but the *actual* runtime behaviour needs `true` (Traefik terminates
TLS, ArgoCD itself serves plain HTTP behind it — see
`gitops/manifests/argocd-config/argocd-cmd-params-cm.yaml`, a separately
gitops-managed ConfigMap that also sets this key to `true`). Whichever
value was last written wins — a `helm upgrade` that doesn't also carry
`true` here silently reverts it to `false` on the next `argocd-server` pod
restart, causing an HTTP→HTTPS redirect loop (`ERR_TOO_MANY_REDIRECTS`).
This bit us once already (2026-07-09, same night as this SSO setup) after
the CP/worker node reboots force-recreated the pod mid-fix.
