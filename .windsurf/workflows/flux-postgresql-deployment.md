---
description: Deploy PostgreSQL with Flux using Medtronic structure pattern
---

# Flux PostgreSQL Deployment Workflow

This workflow documents the complete process we used to deploy PostgreSQL using Flux with the exact Medtronic directory structure and naming conventions. Use this as a reference for deploying to the real Medtronic cluster once VDI access is active.

## Prerequisites

- Kubernetes cluster accessible via `~/.kube/config-homelab`
- CNPG operator v1.28.1 already running in `cnpg-system` namespace
- MinIO already running in `minio-system` namespace
- MinIO endpoint: `http://minio.minio-system.svc.cluster.local:9000`
- MinIO bucket: `cnpg-backups`
- Git repository: `https://github.com/jamilshaikh07/talos-proxmox-gitops`

## Phase 1: Install Flux Controllers (No GitOps Bootstrap)

Install only the controllers needed for manual reconcile (no git remote sync):

```bash
export KUBECONFIG=~/.kube/config-homelab

flux install \
  --components=source-controller,helm-controller,kustomize-controller \
  --namespace=flux-system
```

**Verify:**
```bash
kubectl get pods -n flux-system
# Expected: helm-controller, kustomize-controller, source-controller all Running
```

## Phase 2: Create Medtronic Directory Structure

Mirror the real Medtronic repo structure using "homelab" as the site name:

```bash
cd ~/workspace/homelab/100k/talos-proxmox-gitops/

mkdir -p k8s/flux/clusters/homelab
mkdir -p k8s/flux/sites/homelab/helmreleases
mkdir -p k8s/charts/postgresql-cnpg/templates
```

### Directory Layout:
```
k8s/flux/
├── clusters/homelab/          # Site config bootstrap ONLY
│   ├── kustomization.yaml
│   └── site-config.yaml       # ConfigMap with site settings
├── sites/homelab/             # Workload HelmReleases ONLY
│   ├── kustomization.yaml
│   └── helmreleases/
│       └── postgresql.yaml    # HelmRelease CR
└── flux-sources.yaml          # GitRepository source

k8s/charts/postgresql-cnpg/    # Local Helm chart
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── secret.yaml
    ├── cluster.yaml           # CNPG Cluster CR
    └── scheduledbackup.yaml
```

**Key Rule from Medtronic:**
- `clusters/{site}/` = site-config bootstrap ONLY
- `sites/{site}/` = workload HelmReleases ONLY
- Never mix them — dual-ownership causes Helm annotation conflicts

## Phase 3: Create Site Config (Cluster Layer)

**File:** `k8s/flux/clusters/homelab/site-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: site-config
  namespace: flux-system
data:
  SITE_ID: "homelab"
  SITE_TIMEZONE: "Asia/Kolkata"
  SITE_STORAGE_CLASS: "local-path"
  BARMAN_S3_ENDPOINT: "http://minio.minio-system.svc.cluster.local:9000"
  BARMAN_S3_BUCKET: "cnpg-backups"
  BARMAN_S3_REGION: "us-east-1"
```

**File:** `k8s/flux/clusters/homelab/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - site-config.yaml
```

## Phase 4: Build PostgreSQL Helm Chart

### Chart.yaml
```yaml
apiVersion: v2
name: postgresql-cnpg
description: CloudNativePG PostgreSQL cluster with Barman backup
type: application
version: 0.1.0
appVersion: "17.5"
```

### values.yaml
```yaml
global:
  siteCode: homelab

image:
  repository: ghcr.io/cloudnative-pg/postgresql
  tag: "17.5"

replicaCount: 1

persistence:
  data:
    storageClass: "local-path"
    size: "5Gi"
  wal:
    storageClass: "local-path"
    size: "1Gi"

postgresql:
  database: oee_test
  owner: app
  parameters:
    max_connections: "100"
    shared_buffers: "256MB"
    effective_cache_size: "1GB"
    maintenance_work_mem: "64MB"
    checkpoint_completion_target: "0.9"
    wal_buffers: "16MB"
    default_statistics_target: "100"
    random_page_cost: "1.1"
    effective_io_concurrency: "200"
    work_mem: "2621kB"
    min_wal_size: "80MB"
    max_wal_size: "512MB"

barman:
  serverName: "homelab-postgresql"
  s3:
    endpoint: "http://minio.minio-system.svc.cluster.local:9000"
    bucket: "cnpg-backups"
    region: "us-east-1"
    credentials:
      accessKeyId: "minioadmin"
      secretAccessKey: "minioadmin123"
  backup:
    schedule: "*/5 * * * *"
    retention: "7d"
    compress: "gzip"

resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"

monitoring:
  enablePodMonitor: false
```

### templates/_helpers.tpl
```yaml
{{- define "postgresql-cnpg.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "postgresql-cnpg.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "postgresql-cnpg.namespace" -}}
{{- printf "%s-postgres" .Values.global.siteCode }}
{{- end }}

{{- define "postgresql-cnpg.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "postgresql-cnpg.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

### templates/namespace.yaml
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {{ include "postgresql-cnpg.namespace" . }}
  labels:
    {{- include "postgresql-cnpg.labels" . | nindent 4 }}
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### templates/secret.yaml
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: {{ include "postgresql-cnpg.namespace" . }}
  labels:
    {{- include "postgresql-cnpg.labels" . | nindent 4 }}
type: Opaque
stringData:
  ACCESS_KEY_ID: {{ .Values.barman.s3.credentials.accessKeyId | quote }}
  ACCESS_SECRET_KEY: {{ .Values.barman.s3.credentials.secretAccessKey | quote }}
```

### templates/cluster.yaml
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {{ include "postgresql-cnpg.fullname" . }}
  namespace: {{ include "postgresql-cnpg.namespace" . }}
  labels:
    {{- include "postgresql-cnpg.labels" . | nindent 4 }}
spec:
  instances: {{ .Values.replicaCount }}

  imageName: {{ .Values.image.repository }}:{{ .Values.image.tag }}

  storage:
    storageClass: {{ .Values.persistence.data.storageClass }}
    size: {{ .Values.persistence.data.size }}

  walStorage:
    storageClass: {{ .Values.persistence.wal.storageClass }}
    size: {{ .Values.persistence.wal.size }}

  bootstrap:
    initdb:
      database: {{ .Values.postgresql.database }}
      owner: {{ .Values.postgresql.owner }}

  postgresql:
    parameters:
      {{- range $key, $value := .Values.postgresql.parameters }}
      {{ $key }}: {{ $value | quote }}
      {{- end }}

  monitoring:
    enablePodMonitor: {{ .Values.monitoring.enablePodMonitor }}

  backup:
    barmanObjectStore:
      destinationPath: s3://{{ .Values.barman.s3.bucket }}/{{ .Values.barman.serverName }}
      endpointURL: {{ .Values.barman.s3.endpoint }}
      s3Credentials:
        accessKeyId:
          name: minio-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: minio-credentials
          key: ACCESS_SECRET_KEY
      wal:
        compression: {{ .Values.barman.backup.compress }}
        maxParallel: 2
      data:
        compression: {{ .Values.barman.backup.compress }}
        jobs: 2
    retentionPolicy: {{ .Values.barman.backup.retention | quote }}

  resources:
    requests:
      cpu: {{ .Values.resources.requests.cpu }}
      memory: {{ .Values.resources.requests.memory }}
    limits:
      cpu: {{ .Values.resources.limits.cpu }}
      memory: {{ .Values.resources.limits.memory }}
```

### templates/scheduledbackup.yaml
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: {{ include "postgresql-cnpg.fullname" . }}-scheduled
  namespace: {{ include "postgresql-cnpg.namespace" . }}
  labels:
    {{- include "postgresql-cnpg.labels" . | nindent 4 }}
spec:
  schedule: {{ .Values.barman.backup.schedule | quote }}
  backupOwnerReference: self
  cluster:
    name: {{ include "postgresql-cnpg.fullname" . }}
  immediate: true
  method: barmanObjectStore
```

## Phase 5: Create Flux Sources and HelmRelease

**File:** `k8s/flux/flux-sources.yaml`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: oee-source
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/jamilshaikh07/talos-proxmox-gitops
  ref:
    branch: master
```

**File:** `k8s/flux/sites/homelab/helmreleases/postgresql.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: homelab-postgresql
  namespace: flux-system
spec:
  interval: 10m
  targetNamespace: homelab-postgres
  chart:
    spec:
      chart: ./k8s/charts/postgresql-cnpg
      sourceRef:
        kind: GitRepository
        name: oee-source
        namespace: flux-system
      interval: 1m
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  values:
    nameOverride: "pg"
    fullnameOverride: "homelab-postgresql"
    global:
      siteCode: homelab
    image:
      tag: "17.5"
    replicaCount: 1
    persistence:
      data:
        storageClass: "local-path"
        size: "5Gi"
      wal:
        storageClass: "local-path"
        size: "1Gi"
    barman:
      serverName: "homelab-postgresql"
      s3:
        endpoint: "http://minio.minio-system.svc.cluster.local:9000"
        bucket: "cnpg-backups"
        region: "us-east-1"
      backup:
        schedule: "*/5 * * * *"
        retention: "7d"
```

**File:** `k8s/flux/sites/homelab/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmreleases/postgresql.yaml
```

## Phase 6: Commit and Push to Git

```bash
git add k8s/flux/ k8s/charts/
git commit -m "Add Flux-managed PostgreSQL deployment (Medtronic structure)"
git push
```

## Phase 7: Apply Resources and Reconcile

```bash
export KUBECONFIG=~/.kube/config-homelab

# Apply site-config (cluster layer)
kubectl apply -k k8s/flux/clusters/homelab/

# Apply GitRepository source
kubectl apply -f k8s/flux/flux-sources.yaml

# Apply HelmRelease
kubectl apply -f k8s/flux/sites/homelab/helmreleases/postgresql.yaml

# Trigger reconcile
flux reconcile source git oee-source
flux reconcile helmrelease homelab-postgresql -n flux-system --with-source
```

## Phase 8: Verify Deployment

```bash
# Check Flux controllers
kubectl get pods -n flux-system

# Check GitRepository
flux get sources git

# Check HelmRelease status
flux get helmrelease homelab-postgresql -n flux-system
# Expected: READY=True, revision 0.1.0

# Check PostgreSQL cluster
kubectl get cluster -n homelab-postgres
# Expected: homelab-postgresql, READY=1, "Cluster in healthy state"

# Check pods
kubectl get pods -n homelab-postgres
# Expected: homelab-postgresql-1 Running

# Check backups
kubectl get backup,scheduledbackup -n homelab-postgres
# Expected: Backups completed, ScheduledBackup active

# Check WAL archiving
kubectl exec -n homelab-postgres homelab-postgresql-1 -- \
  psql -U postgres -c "SELECT * FROM pg_stat_archiver;"

# Verify MinIO bucket (port-forward)
kubectl port-forward -n minio-system svc/minio-console 9001:9001
# Open http://localhost:9001 (minioadmin/minioadmin123)
# Navigate to: Buckets → cnpg-backups → homelab-postgresql/
# Expected: base/ and wals/ directories with backup files
```

## Troubleshooting

### Issue 1: Chart Version Not Found
**Error:** `chart "cloudnative-pg" version "X.X.X" not found`

**Solution:** Verify chart version exists in the official CNPG repo:
```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm search repo cnpg/cloudnative-pg --versions
```

### Issue 2: Retention Policy Format Error
**Error:** `spec.backup.retentionPolicy: Invalid value: "RECOVERY WINDOW OF 7 DAYS"`

**Solution:** Use simple format: `7d` (not PostgreSQL PITR syntax)

### Issue 3: Cluster Name Too Long
**Error:** `the maximum length of a cluster name is 50 characters`

**Solution:** Add `fullnameOverride` in HelmRelease values:
```yaml
values:
  fullnameOverride: "homelab-postgresql"
```

### Issue 4: WAL Size Validation Error
**Error:** `min_wal_size: "1GB" should be smaller than WAL volume size`

**Solution:** Adjust WAL parameters to fit within volume:
```yaml
postgresql:
  parameters:
    min_wal_size: "80MB"
    max_wal_size: "512MB"
```

### Issue 5: HelmRelease Stuck on Old Revision
**Solution:** Delete and recreate HelmRelease:
```bash
kubectl delete helmrelease homelab-postgresql -n flux-system
kubectl apply -f k8s/flux/sites/homelab/helmreleases/postgresql.yaml
```

## Key Lessons Learned

1. **Chart versions matter** — Always verify chart exists in the repo
2. **Retention policy format** — Use `7d`, not `RECOVERY WINDOW OF 7 DAYS`
3. **Cluster name length** — Max 50 characters, use `fullnameOverride`
4. **WAL sizing** — Parameters must fit within volume size
5. **Namespace isolation** — Each deployment in separate namespace
6. **Flux reconcile** — Manual trigger required (no auto-sync like ArgoCD)
7. **Medtronic structure** — Keep clusters/ and sites/ separate

## Namespace Isolation Pattern

This deployment demonstrates the Medtronic production pattern:

```
Shared Infrastructure:
├── cnpg-system/              # CNPG operator (cluster-wide)
└── minio-system/             # MinIO S3 storage

Independent Deployments:
├── test-pg/                  # ArgoCD-managed test
│   └── oee-test-cluster
│       └── Backup: s3://cnpg-backups/oee-test-cluster/
│
├── homelab-postgres/         # Flux-managed production
│   └── homelab-postgresql
│       └── Backup: s3://cnpg-backups/homelab-postgresql/
│
└── homelab-postgres-restore/ # Restore testing namespace
    └── restored-cluster
        └── Source: s3://cnpg-backups/homelab-postgresql/
```

**Benefits:**
- ✅ Isolation — Each namespace is independent
- ✅ No Conflicts — Different cluster names, same operator
- ✅ Shared Backup — All use same S3 bucket, different paths
- ✅ Safe Testing — Restore in separate namespace without affecting production
- ✅ Easy Cleanup — `kubectl delete namespace <namespace>`

## Next Steps

1. Test restore in separate namespace
2. Verify PITR (Point-in-Time Recovery)
3. Document backup/restore procedures for Vijay
4. Prepare for Medtronic Atlas deployment once VDI access is active

## Success Criteria

✅ Flux controllers running
✅ HelmRelease READY=True
✅ PostgreSQL cluster healthy
✅ Backups completing every 5 minutes
✅ WAL archiving to MinIO
✅ No conflicts with ArgoCD test deployment
✅ Medtronic directory structure replicated exactly
