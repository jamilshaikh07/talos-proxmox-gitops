# BTS: Access Control & SSO

> Started: 2026-07-09 | Status: Done for 3 apps, more to extend later

## Why this exists

Before this, every public `*.jamilshaikh.in` app relied on its own local login (or, in kagent's case, discovered mid-session, *no* login at all). This doc covers the two-layer access-control pattern now in place for `kagent`, `grafana`, and `argocd` — and the reasoning for the scoping/subject-matching decisions, some of which were non-obvious enough to cost real debugging time.

## Layer 1: Cloudflare Access (edge-level gate)

Sits in front of the Cloudflare Tunnel — enforced before traffic ever reaches the cluster. Three scoped Access Applications, one GitHub identity provider shared across all of them:

| App | Access App ID | Scope |
|---|---|---|
| kagent | `51bce6a0-43a4-438b-8bb0-baf346967e93` | `kagent.jamilshaikh.in` only |
| grafana | `89d2c1ad-99ee-45b0-a44b-2fa38985b499` | `grafana.jamilshaikh.in` only |
| argocd | `7f54e53c-53f2-48df-b324-a942ca64f993` | `argocd.jamilshaikh.in` only |

Deliberately **not** a wildcard `*.jamilshaikh.in` app — that would've instantly gated Coder, Mattermost, and every other public host too, each of which has its own separate login already. Scoped per-hostname now, wildcard is a possible later step if the login flow feels good.

Policy on each: `login_method` = GitHub IdP, `require` = email `jamilshaikh07@gmail.com`. None of this config is in git — Cloudflare Access Apps/Policies/Identity Providers live entirely in Cloudflare's account, not Kubernetes. Full redo-from-scratch steps: `gitops/manifests/kagent/README-secrets.md`.

**Note:** a pre-existing, long-inert Access Application called "homelab" (scoped to bare `jamilshaikh.in`, zero policies, zero IdPs, sitting untouched since April) was found during this work and deliberately left alone rather than reused — reusing it would've meant the new policy applying to the apex domain too, a bigger and less-intentional scope change than asked for.

**Cross-app SSO behavior:** once authenticated via GitHub for *any* Access-protected `*.jamilshaikh.in` app in a browser, Cloudflare Access silently reuses that session for the others — no second GitHub prompt, straight through to each app's own separate login underneath.

## Layer 2: Per-app native login (unchanged for Grafana, replaced for ArgoCD)

- **Grafana:** still its own local admin login. Cloudflare Access doesn't replace it, just gates reachability. Grafana's *own* GitHub OAuth integration (visible under Administration → Authentication, "Not enabled") is a separate, optional step not yet done.
- **ArgoCD:** replaced entirely with GitHub SSO via Argo's built-in Dex. See below — this one had a real gotcha.

## ArgoCD Dex GitHub SSO — the RBAC subject gotcha

Wiring in the Dex connector was mechanical (new GitHub OAuth App, `configs.cm.dex.config` in Helm values, client secret in `argocd-secret` under key `dex.github.clientSecret`). Getting the **RBAC policy subject right** took three attempts, verified against server logs each time rather than guessed:

1. First try: `g, jamilshaikh07, role:admin` (GitHub username) — wrong. ArgoCD's User Info page didn't even show the username.
2. Second try: `g, hi@jamilshaikh.in, role:admin` (the email ArgoCD's own UI displayed as "Username") — also wrong. Login succeeded but "No applications available."
3. Checked `argocd-server` logs directly for the actual `PermissionDenied` enforcement line:
   ```
   permission denied: certificates, get, , sub: 7383132, iat: ...
   ```
   ArgoCD's RBAC subject is the **raw GitHub numeric user ID** (`federated_claims.user_id` in the Dex-issued JWT) — not the email shown in the UI, not the username, not Dex's own opaque `sub` claim. `g, 7383132, role:admin` is what actually worked.

**Lesson:** don't trust what ArgoCD's own UI displays as "Username" for RBAC policy authoring — it's a display-only claim. Pull the actual enforced subject from `argocd-server` logs (`grpc.error="... sub: <value> ..."` on a `PermissionDenied` line) before writing the policy.

## `server.insecure` dual-ownership bug (found and fixed as a side effect)

Discovered while doing the SSO `helm upgrade`: the live Helm values still had `configs.params.server.insecure: false`, while a *separately* gitops-managed ConfigMap (`gitops/manifests/argocd-config/argocd-cmd-params-cm.yaml`) had been setting it to `true` for weeks. Two owners writing the same key — whichever synced last wins, and a `helm upgrade` with the stale `false` in its values would silently regress it back on the next pod restart.

This is exactly what caused an `ERR_TOO_MANY_REDIRECTS` outage earlier the same night (Argo's `argocd-server` pod got recreated by an unrelated control-plane reboot, picked up the stale `false`, and started redirecting HTTP→HTTPS with nowhere for the redirect to land since Traefik only forwards plain HTTP). Fixed permanently by aligning the Helm values with the gitops override (`true`) in the same upgrade that added SSO — see `gitops/manifests/argocd-config/README-sso.md` for the full writeup and why this wasn't fixed by adding *another* gitops-managed ConfigMap (would recreate the same dual-ownership problem for `argocd-cm`/`argocd-rbac-cm`).

## Extending this pattern

Same three-call recipe for any other public host: create a scoped Cloudflare Access Application → attach the existing GitHub IdP → add a `login_method` + `email` policy. Coder and Mattermost are the remaining public `*.jamilshaikh.in` hosts without this layer, as of 2026-07-09.
