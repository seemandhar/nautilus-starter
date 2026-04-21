#!/usr/bin/env bash
# ============================================================================
# Create your personal PersistentVolumeClaim on Ceph.
# Run once per person. Safe to re-run: detects existing PVC.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Check if PVC already exists
if kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "✓ PVC '$PVC_NAME' already exists in namespace '$NAMESPACE':"
  kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"
  exit 0
fi

echo "→ Creating PVC '$PVC_NAME' (${PVC_SIZE}, ${PVC_ACCESS_MODE}, ${PVC_STORAGE_CLASS})..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  storageClassName: ${PVC_STORAGE_CLASS}
  accessModes:
    - ${PVC_ACCESS_MODE}
  resources:
    requests:
      storage: ${PVC_SIZE}
EOF

echo ""
echo "→ Waiting for PVC to bind (usually 5–10 seconds)..."
for i in {1..30}; do
  STATUS=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$STATUS" == "Bound" ]]; then
    echo "✓ PVC bound."
    kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"
    echo ""
    echo "Your PVC is ready. Run ./nrp.sh up to launch a pod that mounts it at /workspace."
    exit 0
  fi
  sleep 1
done

echo "✗ PVC did not bind within 30s. Current status:"
kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"
echo ""
echo "Try: kubectl describe pvc $PVC_NAME -n $NAMESPACE"
exit 1
