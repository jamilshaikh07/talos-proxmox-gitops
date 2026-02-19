# Grafana Dashboards as Code

This directory contains Grafana dashboards as ConfigMaps that are automatically loaded into Grafana via the sidecar container.

## How to Add a Dashboard

1. **Export from Grafana UI**:
   - Go to Grafana → Dashboard → Settings → JSON Model
   - Copy the JSON

2. **Create a ConfigMap**:
   ```bash
   kubectl create configmap my-dashboard \
     --from-file=dashboard.json \
     --namespace=monitoring \
     --dry-run=client -o yaml > manifests/grafana-dashboards/my-dashboard.yaml
   ```

3. **Add the required labels**:
   ```yaml
   metadata:
     labels:
       grafana_dashboard: "1"
       grafana_folder: "Custom"  # Optional: organize in folders
   ```

4. **Commit and push** - ArgoCD will sync and Grafana sidecar will auto-load it

## Dashboard Organization

Dashboards can be organized into folders using the `grafana_folder` annotation:
- `grafana_folder: "Kubernetes"` - For cluster monitoring
- `grafana_folder: "Applications"` - For custom apps
