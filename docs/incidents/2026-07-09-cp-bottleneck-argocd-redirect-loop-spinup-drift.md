# Incident: CP CPU Bottleneck, ArgoCD Redirect Loop, spinup.in Stale Image

**Date:** 2026-07-09
**Severity:** Mixed — one proactive fix (CP bottleneck), two real production bugs found and fixed same session (ArgoCD UI inaccessible, spinup.in serving an old build)
**Resolved by:** Terraform core rebalance, ArgoCD Helm values fix, control-plane manifest re-apply

---

## Part 1: Control-plane CPU bottleneck (proactive)

openclaw's own bottleneck-analysis flagged `talos-cp-01` at 62% CPU requests on only 2 vCPUs, while `talos-wk-01` sat at 44% on 6. Root cause: the original 2+6 split (documented in `variables.tf`) was sized for the physical host's 8 logical CPUs assuming the control-plane would stay lightly loaded — it didn't, as the cluster grew.

**Fix:** rebalanced to 4+4 via `terraform apply` (in-place `cores` resize, confirmed via `terraform plan` as `0 add, 0 destroy` before applying) — same total host allocation, redistributed. Applied worker first (lower risk, no API server impact), verified cluster health, then control plane (accepted ~30s `kube-apiserver` downtime during the VM reboot, single-CP cluster with no HA to fall back on).

Found and fixed a **pre-existing, unrelated bug** while validating the `terraform plan`: a `coalesce()` call on `worker_longhorn_disk_size` errored whenever both the per-worker override and the default were empty — which they always are, since this cluster doesn't use Longhorn. Blocked every plan/apply regardless of the core-count change. Fixed with `try(coalesce(...), "")`.

Also cleaned up 39 stale `Released` PersistentVolumes (~136Gi) from removed apps (`test-pg`, `pnl-postgres*`, `homelab-postgres*`, old tailscale/monitoring/homarr claims) — all `Retain` reclaim policy, safe to delete since no live PVC referenced any of them.

## Part 2: ArgoCD `ERR_TOO_MANY_REDIRECTS`

Surfaced mid-session as `argocd.jamilshaikh.in` became completely inaccessible via browser.

**Root cause:** `argocd-server`'s `ARGOCD_SERVER_INSECURE` env var reads from the `argocd-cmd-params-cm` ConfigMap via `configMapKeyRef` — resolved **once, at pod creation**, not live. That ConfigMap has two competing owners: the Helm release (`configs.params.server.insecure: false` in chart values) and a separately gitops-managed override (`gitops/manifests/argocd-config/argocd-cmd-params-cm.yaml`, `server.insecure: "true"`). The CP reboot from Part 1 force-recreated the `argocd-server` pod, and it happened to bake in the stale `false` rather than the corrected `true`.

**Fix (immediate):** confirmed the ConfigMap's live value was correct (`true`), then `kubectl rollout restart deploy/argocd-server` — new pod read the current value correctly.

**Fix (permanent, done later the same night):** the dual-ownership problem itself resurfaced during the ArgoCD SSO work (`docs/09-access-control-sso.md`) and was fixed by aligning the Helm values with the gitops override in that same `helm upgrade`, rather than letting them keep fighting.

Also found: `local-path-provisioner` and `promtail` ArgoCD Applications briefly showed stale `Unknown`/`Progressing` status from the same reboot window — both were a caching artifact, not real breakage (confirmed via `kubectl get pods` showing healthy pods underneath), fixed with a hard-refresh (`argocd.argoproj.io/refresh: hard` annotation).

## Part 3: spinup.in serving a stale build

User reported a previously-applied UI theme had "disappeared."

**Root cause:** the live `control-plane` Deployment in `paas-system` had `imagePullPolicy: IfNotPresent` despite the manifest in git (`gitops/manifests-adjacent vercel-clone repo, manifests/04-deploy-control-plane.yaml`) specifying `Always` since its very first commit — pure drift from an unknown past manual edit, unrelated to anything this session. Combined with the image tag being mutable (`:latest`), any pod restart on a node with a cached layer under that tag silently kept serving an old build instead of pulling the registry's actual current `latest` digest.

Confirmed via comparing the running pod's `imageID` digest against the registry's `latest` manifest digest directly (`docker registry v2 API`, authenticated via the existing `registry-dockercfg` pull secret) — they didn't match.

**Fix:** re-applied `manifests/04-deploy-control-plane.yaml` (restores `imagePullPolicy: Always`, matches what git already said), then `kubectl rollout restart deploy/control-plane` to force a fresh pull. Confirmed new pod's `imageID` matched the registry's current digest.

## Cross-cutting lesson

Every distinct bug this session traced back to the same shape: **something that's supposed to be reconciled continuously actually only gets applied once, at creation/restart time** — `configMapKeyRef` env vars, `imagePullPolicy: IfNotPresent` on a mutable tag, dual-owned ConfigMaps where "last writer wins" isn't visible until the next restart. None of these are obviously wrong when read in isolation; they only surface when *something else* (a node reboot, in two of three cases here) triggers the restart that exposes the staleness.
