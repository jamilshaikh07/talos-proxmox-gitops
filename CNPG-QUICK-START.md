# CNPG Backup/Restore Test — Quick Start

## TL;DR

Test the Medtronic PostgreSQL backup pattern on your homelab before production deployment.

```bash
cd ~/workspace/homelab/100k/talos-proxmox-gitops
./scripts/deploy-cnpg-test.sh
```

## What This Deploys

1. **MinIO** (minio-system) — S3-compatible storage
2. **CloudNativePG Operator** (cnpg-system) — PostgreSQL cluster manager
3. **Test PostgreSQL Cluster** (test-pg) — 1 instance, 5Gi storage, PostgreSQL 17.5
4. **Automated Backups** — Every 5 minutes to MinIO S3 bucket

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Homelab Test                              │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │ oee-test-cluster │────────▶│ MinIO S3 Bucket  │         │
│  │   PostgreSQL     │ Barman  │  cnpg-backups/   │         │
│  │     17.5         │ Backup  │                  │         │
│  │   1 instance     │         │                  │         │
│  │   5Gi storage    │         │                  │         │
│  └──────────────────┘         └──────────────────┘         │
│         │                              │                     │
│         │ WAL Archive (continuous)     │                     │
│         └──────────────────────────────┘                     │
│                                                              │
│  ┌──────────────────┐                                       │
│  │oee-test-restore  │◀────── Bootstrap from backup         │
│  │   (PITR test)    │         (any point in time)          │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘

                            ▼ Replicate to ▼

┌─────────────────────────────────────────────────────────────┐
│              Medtronic Atlas Cluster (MECC/PNL)             │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │ mecc-postgresql  │────────▶│ Atlas S3 Bucket  │         │
│  │   PostgreSQL     │ Barman  │  (EU region)     │         │
│  │     17.5         │ Backup  │                  │         │
│  │   3 instances    │         │                  │         │
│  │   100Gi storage  │         │                  │         │
│  └──────────────────┘         └──────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## Testing Workflow

### 1. Deploy (Automated)

```bash
./scripts/deploy-cnpg-test.sh
```

This script will:
- ✅ Check cluster connectivity
- ✅ Commit and push changes to Git (with confirmation)
- ✅ Wait for ArgoCD to sync (waves 3, 4, 5)
- ✅ Verify all pods are running
- ✅ Display next steps

### 2. Create Test Data

```bash
# Connect to PostgreSQL
kubectl exec -it oee-test-cluster-1 -n test-pg -- psql -U app -d oee_test

# Inside psql:
CREATE TABLE backup_test (
    id SERIAL PRIMARY KEY,
    test_data VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO backup_test (test_data) VALUES
    ('Pre-backup record 1'),
    ('Pre-backup record 2'),
    ('Pre-backup record 3');

SELECT * FROM backup_test ORDER BY id;
SELECT NOW();  -- ⚠️ Note this timestamp for PITR
\q
```

### 3. Wait for Backup

Backups run every 5 minutes (scheduled). Watch for completion:

```bash
kubectl get backup -n test-pg -w
```

Or trigger manual backup:

```bash
kubectl apply -f gitops/manifests/test-pg/05-manual-backup.yaml
```

### 4. Verify Backup in MinIO

```bash
# Port-forward to MinIO console
kubectl port-forward -n minio-system svc/minio-console 9001:9001

# Open browser: http://localhost:9001
# Login: minioadmin / minioadmin123
# Navigate: Buckets → cnpg-backups → oee-test-cluster/
```

You should see:
- `base/` — Full base backups
- `wals/` — WAL archive files

### 5. Test Restore (PITR Drill)

Deploy restore cluster:

```bash
kubectl apply -f gitops/manifests/test-pg/06-restore-cluster.yaml
```

Wait for restore to complete:

```bash
kubectl get cluster oee-test-restore -n test-pg -w
# Wait for: "Cluster in healthy state"
```

Verify restored data:

```bash
kubectl exec -it oee-test-restore-1 -n test-pg -- \
  psql -U app -d oee_test -c "SELECT * FROM backup_test ORDER BY id;"
```

**Expected:** All 3 test records should be present.

### 6. Test Point-in-Time Recovery (Optional)

Edit `06-restore-cluster.yaml` and uncomment the `recoveryTarget` section:

```yaml
bootstrap:
  recovery:
    source: oee-test-cluster
    recoveryTarget:
      targetTime: "2026-04-21 10:30:00.00000+00"  # Use timestamp from step 2
```

Delete and recreate restore cluster:

```bash
kubectl delete cluster oee-test-restore -n test-pg
kubectl apply -f gitops/manifests/test-pg/06-restore-cluster.yaml
```

Verify data is restored to the exact timestamp specified.

## Useful Commands

### Check cluster status

```bash
kubectl get cluster -n test-pg
kubectl describe cluster oee-test-cluster -n test-pg
```

### Check backup status

```bash
kubectl get backup -n test-pg
kubectl describe backup <backup-name> -n test-pg
```

### View PostgreSQL logs

```bash
kubectl logs -n test-pg oee-test-cluster-1
```

### View CNPG operator logs

```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### Connect to PostgreSQL

```bash
# Get app password
APP_PASSWORD=$(kubectl get secret app-credentials -n test-pg -o jsonpath='{.data.password}' | base64 -d)

# Connect
kubectl exec -it oee-test-cluster-1 -n test-pg -- psql -U app -d oee_test
```

### Check WAL archiving

```bash
kubectl exec -it oee-test-cluster-1 -n test-pg -- \
  psql -U postgres -c "SELECT * FROM pg_stat_archiver;"
```

## Troubleshooting

### Cluster stuck in "Creating primary instance"

```bash
kubectl describe cluster oee-test-cluster -n test-pg
kubectl logs -n test-pg oee-test-cluster-1
```

Common issues:
- PVC not bound (check StorageClass)
- Image pull failure (check network)
- Resource limits (check node capacity)

### Backup failing

```bash
kubectl describe backup <backup-name> -n test-pg
kubectl logs -n test-pg oee-test-cluster-1 | grep -i backup
```

Common issues:
- MinIO credentials incorrect
- MinIO endpoint unreachable
- S3 bucket doesn't exist

### Restore failing

```bash
kubectl describe cluster oee-test-restore -n test-pg
kubectl logs -n test-pg oee-test-restore-1
```

Common issues:
- No backups available in MinIO
- WAL files missing
- Invalid recovery target time

## Cleanup

Remove restore cluster:

```bash
kubectl delete cluster oee-test-restore -n test-pg
```

Remove entire test environment:

```bash
kubectl delete -f gitops/manifests/test-pg/
kubectl delete namespace test-pg
```

Remove from ArgoCD (will auto-delete):

```bash
git rm gitops/apps/test-pg.yaml
git commit -m "Remove CNPG test environment"
git push
```

## Medtronic Production Differences

| Aspect | Homelab Test | Medtronic Production |
|--------|-------------|---------------------|
| **Instances** | 1 (primary only) | 3 (1 primary + 2 standby) |
| **Storage** | 5Gi data, 1Gi WAL | 100Gi data, 25Gi WAL |
| **StorageClass** | `local-path` | `mdt-esa-raid-1-compression-policy` |
| **S3 Backend** | MinIO (local) | Atlas S3 (EU region) |
| **Backup Schedule** | Every 5 minutes | Daily at midnight |
| **Namespace** | `test-pg` | `pnl-postgres` or `mecc-postgres` |
| **Secrets** | Plain K8s Secret | SOPS-encrypted + Vault |

## Next Steps

1. ✅ Complete backup/restore test on homelab
2. 📝 Document RTO (Recovery Time Objective)
3. 📋 Update Medtronic Evidence Pack with procedure
4. 🔄 Adapt manifests for Atlas cluster (see `k8s/charts/postgresql/` in medtronic-oee-2026 repo)
5. ⏳ Wait for D-T04 (VDI access) to clear
6. 🚀 Execute on MECC non-prod cluster
7. ✅ Report back to Vijay B. with test results

## References

- CloudNativePG Docs: https://cloudnative-pg.io/
- Barman Backup: https://cloudnative-pg.io/documentation/current/backup_recovery/
- PITR: https://cloudnative-pg.io/documentation/current/recovery/
- Medtronic Spec: `~/workspace/medtronics/improving-oee/medtronic-oee-2026/_bmad-output/engagement-backlog.md` (Story 6.2)
