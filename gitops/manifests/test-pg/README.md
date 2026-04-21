# CNPG + Barman/S3 Backup/Restore Test

This directory contains manifests for testing the CloudNativePG + Barman backup/restore pattern on homelab before deploying to Medtronic Atlas cluster.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    test-pg namespace                         │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │ oee-test-cluster │────────▶│ MinIO S3 Bucket  │         │
│  │   (Primary)      │ Barman  │  cnpg-backups/   │         │
│  │  PostgreSQL 17.5 │ Backup  │ oee-test-cluster │         │
│  └──────────────────┘         └──────────────────┘         │
│         │                              │                     │
│         │ WAL Archive                  │                     │
│         └──────────────────────────────┘                     │
│                                                              │
│  ┌──────────────────┐                                       │
│  │oee-test-restore  │◀────── Bootstrap from backup         │
│  │   (Restored)     │         (PITR capable)                │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

## Files

- `00-namespace.yaml` — test-pg namespace with pod security
- `01-minio-secret.yaml` — MinIO S3 credentials
- `02-cluster.yaml` — Primary PostgreSQL cluster + app credentials
- `03-scheduled-backup.yaml` — Automated backup every 5 minutes
- `04-test-data.sql` — SQL script to create test data
- `05-manual-backup.yaml` — Manual backup trigger (optional)
- `06-restore-cluster.yaml` — Restore cluster from backup (Phase 6)

## Deployment Steps

### Phase 1-4: Deploy Infrastructure + Primary Cluster

All handled by ArgoCD app-of-apps pattern. Just commit and push:

```bash
cd ~/workspace/homelab/100k/talos-proxmox-gitops
git add gitops/apps/minio.yaml gitops/apps/cnpg.yaml gitops/apps/test-pg.yaml
git add gitops/manifests/test-pg/
git commit -m "Add CNPG + MinIO backup test environment"
git push
```

ArgoCD will deploy in order:
1. MinIO (wave 3)
2. CNPG operator (wave 4)
3. test-pg cluster (wave 5)

### Phase 5: Create Test Data + Verify Backup

Wait for cluster to be ready:

```bash
export KUBECONFIG=~/.kube/config-homelab
kubectl get cluster -n test-pg -w
```

When status shows `Cluster in healthy state`, connect and create test data:

```bash
# Get app password
APP_PASSWORD=$(kubectl get secret app-credentials -n test-pg -o jsonpath='{.data.password}' | base64 -d)

# Connect to primary pod
kubectl exec -it oee-test-cluster-1 -n test-pg -- psql -U app -d oee_test

# Inside psql, run:
\i /path/to/test-data.sql
# Or manually:
CREATE TABLE backup_test (id SERIAL PRIMARY KEY, test_data VARCHAR(255), created_at TIMESTAMP DEFAULT NOW());
INSERT INTO backup_test (test_data) VALUES ('Pre-backup record 1'), ('Pre-backup record 2'), ('Pre-backup record 3');
SELECT * FROM backup_test;
SELECT NOW();  -- Note this timestamp for PITR
\q
```

Verify backup completed:

```bash
kubectl get backup -n test-pg
kubectl describe backup -n test-pg
```

Check MinIO bucket:

```bash
# Port-forward to MinIO console
kubectl port-forward -n minio-system svc/minio-console 9001:9001

# Open http://localhost:9001
# Login: minioadmin / minioadmin123
# Navigate to cnpg-backups bucket → oee-test-cluster/
```

### Phase 6: Test Restore (PITR Drill)

Deploy restore cluster (DO NOT commit this to Git yet — test manually first):

```bash
kubectl apply -f gitops/manifests/test-pg/06-restore-cluster.yaml
```

Wait for restore to complete:

```bash
kubectl get cluster oee-test-restore -n test-pg -w
```

Verify restored data:

```bash
kubectl exec -it oee-test-restore-1 -n test-pg -- psql -U app -d oee_test -c "SELECT * FROM backup_test ORDER BY id;"
```

Expected output: All 3 (or 5) test records should be present.

## Verification Checklist

- [ ] MinIO pod running in minio-system namespace
- [ ] CNPG operator pod running in cnpg-system namespace
- [ ] oee-test-cluster shows "Cluster in healthy state"
- [ ] ScheduledBackup created and first backup completed
- [ ] Backup visible in MinIO bucket (cnpg-backups/oee-test-cluster/)
- [ ] WAL files being archived to MinIO
- [ ] Test data inserted successfully
- [ ] Manual backup triggered and completed
- [ ] Restore cluster deployed and healthy
- [ ] Restored cluster contains all test data

## Troubleshooting

### Cluster not starting

```bash
kubectl describe cluster oee-test-cluster -n test-pg
kubectl logs -n test-pg -l cnpg.io/cluster=oee-test-cluster
```

### Backup failing

```bash
kubectl describe backup -n test-pg
kubectl logs -n test-pg -l cnpg.io/cluster=oee-test-cluster | grep -i backup
```

### MinIO connection issues

```bash
# Test MinIO connectivity from test-pg namespace
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n test-pg -- \
  curl -v http://minio.minio-system.svc.cluster.local:9000
```

### Check CNPG operator logs

```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

## Cleanup

To remove everything:

```bash
kubectl delete cluster oee-test-restore -n test-pg  # if created
kubectl delete -f gitops/manifests/test-pg/
kubectl delete namespace test-pg
```

To remove from ArgoCD (will auto-delete resources):

```bash
git rm gitops/apps/test-pg.yaml
git commit -m "Remove test-pg"
git push
```

## Next Steps

Once validated on homelab:

1. Document RTO (Recovery Time Objective) — how long restore took
2. Document procedure in Medtronic Evidence Pack
3. Adapt manifests for Medtronic Atlas cluster:
   - Change StorageClass: `local-path` → `mdt-esa-raid-1-compression-policy`
   - Change S3 endpoint to Atlas-provided endpoint
   - Scale up: 1 instance → 3 instances (1 primary + 2 standby)
   - Increase storage: 5Gi → 100Gi data, 1Gi → 25Gi WAL
   - Use SOPS-encrypted secrets for production credentials
4. Execute on MECC non-prod cluster once VDI access (D-T04) is granted
