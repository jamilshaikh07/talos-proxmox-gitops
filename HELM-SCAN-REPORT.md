# Helm Release Scan Report

## Summary

| Priority | Count |
|----------|-------|
| 🔴 Critical | 0 |
| 🟠 Major | 1 |
| 🟡 Minor | 6 |
| ✅ Current | 10 |

## Releases

| Status | Chart | Current | Latest | Namespace | Source |
|--------|-------|---------|--------|-----------|--------|
| 🟠 | kube-prometheus-stack | 77.6.2 | 79.12.0 | monitoring | `prometheus-stack.yaml:None` |
| 🟡 | cert-manager | v1.18.2 | v1.19.1 | cert-manager | `cert-manager.yaml:None` |
| 🟡 | cilium | 1.16.5 | 1.18.4 | kube-system | `cilium.yaml:None` |
| 🟡 | homarr | 8.4.0 | 8.4.3 | homelab | `homarr.yaml:None` |
| 🟡 | metallb | 0.15.2 | 0.15.3 | metallb-system | `metallb.yaml:None` |
| 🟡 | metrics-server | 3.12.2 | 3.13.0 | kube-system | `metrics-server.yaml:None` |
| 🟡 | promtail | 6.16.6 | 6.17.1 | monitoring | `promtail.yaml:None` |
| ✅ | k8s-gateway | 2.4.0 | 2.4.0 | kube-system | `coredns-k8s-gateway.yaml:None` |
| ✅ | kubernetes-event-exporter | 3.6.3 | ? | monitoring | `kubernetes-event-exporter.yaml:None` |
| ✅ | loki | 6.46.0 | 6.46.0 | monitoring | `loki.yaml:None` |
| ✅ | longhorn | 1.10.1 | 1.10.1 | longhorn-system | `longhorn.yaml:None` |
| ✅ | minio | 5.3.0 | ? | minio-system | `minio.yaml:None` |
| ✅ | nfs-subdir-external-provisioner | 4.0.18 | 4.0.18 | nfs-provisioner | `nfs-provisioner.yaml:None` |
| ✅ | tempo | 1.24.1 | 1.24.1 | monitoring | `tempo.yaml:None` |
| ✅ | traefik | 37.4.0 | 37.4.0 | traefik-system | `traefik.yaml:None` |
| ✅ | trust-manager | v0.20.2 | v0.20.2 | cert-manager | `trust-manager.yaml:None` |
| ✅ | uptime-kuma | 2.24.0 | 2.24.0 | monitoring | `uptime-kuma.yaml:None` |