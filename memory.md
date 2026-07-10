# Memory

## Decisions
- Keep Proxmox SSH tunnel as the primary remote access path.
- Do not use in-cluster Tailscale router for node access due to node IP side effects.
- Keep infra persistent; do not optimize for frequent teardown.

## Reliability Rules
- Always run terraform plan before apply.
- After Terraform apply, run sync-inventory.
- For new workers, run planned-dhcp and update OPNsense reservations.
- For worker removal, drain first and verify no local-path PVC dependency.
- Re-run layer2 after topology changes.

## Known Risks
- Node-local storage means workload data can be lost on node removal.
- Single Proxmox node implies no HA and quorum warning is expected.
- Manual DHCP drift can break deterministic node addressing.
- `argocd-cm` / `argocd-cmd-params-cm` / `argocd-rbac-cm` have TWO owners: the Helm release's own values AND separate gitops-managed ConfigMap overrides in `gitops/manifests/argocd-config/`. Whichever synced/restarted last wins — any `helm upgrade` that doesn't carry the gitops-side value too will silently regress it on the next `argocd-server` pod restart. Caused a real `ERR_TOO_MANY_REDIRECTS` outage on 2026-07-09 (`server.insecure` flipped back to Helm's default `false`). Always check the live ConfigMap value before any ArgoCD `helm upgrade`, not just the values file being applied.
- A pod's `configMapKeyRef`/`secretKeyRef` env vars resolve **once, at pod creation** — not live. A ConfigMap/Secret update alone does nothing until something restarts the pod. This is *by design* (not a bug) but easy to forget when debugging "I already fixed the config, why is it still broken."
- ArgoCD's RBAC policy subject for Dex/GitHub SSO logins is the raw GitHub **numeric user ID** (`federated_claims.user_id` in the JWT), not the email or username shown anywhere in ArgoCD's own UI. Verify against `argocd-server` logs (`PermissionDenied ... sub: <value>`) before writing `g, <subject>, role:X` policy lines — see `docs/09-access-control-sso.md`.
- `imagePullPolicy: IfNotPresent` on a mutable tag (`:latest`) silently serves stale cached image layers on any pod restart if the node already has a copy — even if the registry's tag has moved on. Caused spinup.in to serve an old build for an unknown period on 2026-07-09. Any self-deploying app using a mutable tag needs `imagePullPolicy: Always`, and it's worth periodically checking live Deployments haven't drifted from what git says (this one had, from an unknown past manual edit).

## Quick Recovery Paths
### Cluster not reachable
1. make tunnel
2. kubectl get nodes
3. make status

### Talos config drift
1. make sync-inventory
2. make layer2

### GitOps drift
1. make layer3
2. make status-apps

## Upgrade Readiness Notes
- Before host hardware upgrade:
  - export planned DHCP mappings
  - capture current VM resources
  - verify layer2 and layer3 rerun cleanly
- After upgrade:
  - scale-plan first
  - scale-apply in controlled increments
  - verify nodes and workloads after each step
