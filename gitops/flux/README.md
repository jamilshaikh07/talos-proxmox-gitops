# Flux GitOps Directory
#
# Structure:
#   flux-system/    — Core Flux bootstrap manifests (GitRepository + root Kustomization)
#   apps/           — Apps managed exclusively by Flux (HelmRelease / Kustomization)
#
# Separation of concerns:
#   gitops/apps/    → ArgoCD manages these  (app-of-apps pattern)
#   gitops/flux/    → Flux manages these    (GitRepository + Kustomization chain)
#
# This lets you run both tools side-by-side to compare behaviour.
