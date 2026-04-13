# Skills

## Goal
Define repeatable operational skills for this homelab so changes remain reliable over time.

## Skill: Daily Operations
- make status
- make status-apps
- make talos-health
- Action: investigate drift if nodes are NotReady or apps are OutOfSync.

## Skill: Safe Scaling
### Scale up
1. make scale-plan WORKER_COUNT=<n> WORKER_MEMORY=<mb> WORKER_CORES=<n>
2. make scale-apply WORKER_COUNT=<n> WORKER_MEMORY=<mb> WORKER_CORES=<n>
3. make planned-dhcp
4. update OPNsense reservations if needed
5. make layer2
6. validate with make status

### Scale down
1. make drain-node NODE=<worker-name>
2. verify no critical local-path PVC is pinned to that node
3. make scale-plan WORKER_COUNT=<smaller-n>
4. make scale-apply WORKER_COUNT=<smaller-n>
5. make layer2
6. validate with make status and make status-apps

## Skill: Cluster Reconciliation
- Trigger when inventory, Talos patches, or node topology changes.
- Commands:
  - make sync-inventory
  - make layer2
  - make label-nodes

## Skill: GitOps Reconciliation
- Trigger when app manifests or Helm values change.
- Commands:
  - make layer3
  - make status-apps

## Skill: Access Recovery
- make tunnel
- kubectl get nodes
- make tunnel-stop

## Skill: Reliability Hardening
- Put public services behind Cloudflare Access.
- Use OIDC for Grafana and ArgoCD.
- Periodically test restore for stateful services.
- Keep a change log for every scale-down event.
