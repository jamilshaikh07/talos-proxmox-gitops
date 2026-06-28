# Homelab BTS (Behind The Scenes)

Engineering decisions, architecture choices, and the *why* behind everything in this cluster.
Not a tutorial — a running record of what was built, why it was built that way, and what was learned.

## Index

| Doc | What it covers |
|---|---|
| [Cluster Foundation](./01-cluster-foundation.md) | Talos + Proxmox + Terraform + Ansible — why this stack |
| [GitOps Layer](./02-gitops-layer.md) | ArgoCD + FluxCD side-by-side, app-of-apps pattern |
| [Networking](./03-networking.md) | OPNsense, MetalLB, Traefik, Cloudflare tunnel, external-dns |
| [Observability](./04-observability.md) | Victoria Metrics, Loki, Promtail, Grafana, Uptime Kuma |
| [Storage & Backups](./05-storage-backups.md) | local-path, MinIO, Velero, CNPG barman — the full backup chain |
| [spinup.in PaaS](./06-spinup-paas.md) | Self-hosted Vercel clone — architecture, live tenant workloads |
| [openclaw AI SRE](./07-openclaw-ai-sre.md) | AI SRE agent — Phase 1–3, Haiku model chain, Mattermost delivery, cron architecture |

---

*Updated as the cluster evolves. Each doc captures decisions at the time they were made.*
