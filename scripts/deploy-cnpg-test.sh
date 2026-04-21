#!/usr/bin/env bash
# Deploy CNPG + MinIO backup/restore test environment
# Usage: ./scripts/deploy-cnpg-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-homelab}"

echo "═══════════════════════════════════════════════════════════"
echo "  CNPG + Barman/S3 Backup Test Deployment"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check if we're in the right directory
if [[ ! -f "$REPO_ROOT/gitops/app-of-apps.yaml" ]]; then
    echo "❌ Error: Must run from talos-proxmox-gitops repo root"
    exit 1
fi

# Check kubectl connectivity
echo "🔍 Checking cluster connectivity..."
if ! kubectl get nodes &>/dev/null; then
    echo "❌ Error: Cannot connect to cluster. Check KUBECONFIG=$KUBECONFIG"
    exit 1
fi

kubectl get nodes
echo ""

# Phase 1: Check if MinIO is already deployed
echo "📦 Phase 1: Checking MinIO deployment..."
if kubectl get namespace minio-system &>/dev/null; then
    echo "✅ minio-system namespace exists"
    if kubectl get pods -n minio-system | grep -q minio; then
        echo "✅ MinIO pod already running"
    else
        echo "⚠️  MinIO namespace exists but no pods running"
    fi
else
    echo "⏳ MinIO will be deployed by ArgoCD (wave 3)"
fi
echo ""

# Phase 2: Check if CNPG operator is deployed
echo "🔧 Phase 2: Checking CNPG operator..."
if kubectl get crd clusters.postgresql.cnpg.io &>/dev/null; then
    echo "✅ CNPG CRDs already installed"
    if kubectl get pods -n cnpg-system &>/dev/null; then
        echo "✅ CNPG operator running"
    fi
else
    echo "⏳ CNPG operator will be deployed by ArgoCD (wave 4)"
fi
echo ""

# Phase 3: Git status check
echo "📝 Phase 3: Checking Git status..."
cd "$REPO_ROOT"

if git diff --quiet gitops/apps/minio.yaml gitops/apps/cnpg.yaml gitops/apps/test-pg.yaml gitops/manifests/test-pg/ 2>/dev/null; then
    echo "✅ All files already committed"
else
    echo "⚠️  Uncommitted changes detected. Files to commit:"
    git status --short gitops/apps/minio.yaml gitops/apps/cnpg.yaml gitops/apps/test-pg.yaml gitops/manifests/test-pg/ 2>/dev/null || true
    echo ""
    read -p "Commit and push these changes? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add gitops/apps/minio.yaml gitops/apps/cnpg.yaml gitops/apps/test-pg.yaml gitops/manifests/test-pg/
        git commit -m "Add CNPG + MinIO backup/restore test environment

- MinIO standalone deployment for S3-compatible storage
- CloudNativePG operator v1.28.1 (PostgreSQL 17.5)
- Test cluster: oee-test-cluster (1 instance, 5Gi storage)
- Automated backups every 5 minutes to MinIO
- Restore cluster manifest for PITR testing

Replicates Medtronic production pattern at homelab scale."
        
        echo ""
        read -p "Push to remote? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git push
            echo "✅ Changes pushed to remote"
        else
            echo "⚠️  Changes committed locally but NOT pushed"
        fi
    else
        echo "⚠️  Skipping commit. Deploy manually with: kubectl apply -f gitops/manifests/test-pg/"
    fi
fi
echo ""

# Phase 4: Wait for ArgoCD to sync
echo "⏳ Phase 4: Waiting for ArgoCD to sync applications..."
echo "   This may take 1-3 minutes for ArgoCD to detect and sync..."
echo ""

# Wait for MinIO
echo "   Waiting for MinIO (wave 3)..."
for i in {1..60}; do
    if kubectl get pods -n minio-system 2>/dev/null | grep -q "minio.*Running"; then
        echo "   ✅ MinIO pod is Running"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for CNPG operator
echo "   Waiting for CNPG operator (wave 4)..."
for i in {1..60}; do
    if kubectl get pods -n cnpg-system 2>/dev/null | grep -q "cloudnative-pg.*Running"; then
        echo "   ✅ CNPG operator is Running"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for test-pg cluster
echo "   Waiting for oee-test-cluster (wave 5)..."
for i in {1..120}; do
    if kubectl get cluster oee-test-cluster -n test-pg &>/dev/null; then
        STATUS=$(kubectl get cluster oee-test-cluster -n test-pg -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$STATUS" == "Cluster in healthy state" ]]; then
            echo "   ✅ oee-test-cluster is healthy"
            break
        else
            echo -n "."
        fi
    else
        echo -n "."
    fi
    sleep 5
done
echo ""

# Phase 5: Verify deployment
echo "✅ Phase 5: Deployment verification"
echo ""
echo "MinIO:"
kubectl get pods -n minio-system
echo ""
echo "CNPG Operator:"
kubectl get pods -n cnpg-system
echo ""
echo "PostgreSQL Cluster:"
kubectl get cluster -n test-pg
kubectl get pods -n test-pg
echo ""
echo "Backups:"
kubectl get backup -n test-pg 2>/dev/null || echo "No backups yet (scheduled every 5 minutes)"
echo ""

# Phase 6: Next steps
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1️⃣  Create test data:"
echo "   kubectl exec -it oee-test-cluster-1 -n test-pg -- psql -U app -d oee_test"
echo "   Inside psql:"
echo "   CREATE TABLE backup_test (id SERIAL PRIMARY KEY, test_data VARCHAR(255), created_at TIMESTAMP DEFAULT NOW());"
echo "   INSERT INTO backup_test (test_data) VALUES ('Test 1'), ('Test 2'), ('Test 3');"
echo "   SELECT * FROM backup_test;"
echo "   SELECT NOW();  -- Note this timestamp"
echo "   \\q"
echo ""
echo "2️⃣  Wait for backup (every 5 minutes):"
echo "   kubectl get backup -n test-pg -w"
echo ""
echo "3️⃣  Verify backup in MinIO:"
echo "   kubectl port-forward -n minio-system svc/minio-console 9001:9001"
echo "   Open: http://localhost:9001 (minioadmin / minioadmin123)"
echo "   Check: cnpg-backups bucket → oee-test-cluster/"
echo ""
echo "4️⃣  Test restore:"
echo "   kubectl apply -f gitops/manifests/test-pg/06-restore-cluster.yaml"
echo "   kubectl get cluster oee-test-restore -n test-pg -w"
echo "   kubectl exec -it oee-test-restore-1 -n test-pg -- psql -U app -d oee_test -c 'SELECT * FROM backup_test;'"
echo ""
echo "📖 Full documentation: gitops/manifests/test-pg/README.md"
echo ""
