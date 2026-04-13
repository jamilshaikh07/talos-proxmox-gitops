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
