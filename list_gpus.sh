#!/usr/bin/env bash
# ============================================================================
# List GPU types available in the cluster, and count free ones per type.
# ============================================================================
set -euo pipefail

echo "GPU types currently in the cluster:"
echo ""
kubectl get nodes -L nvidia.com/gpu.product,nvidia.com/gpu.count 2>/dev/null \
  | awk 'NR==1 || $6 != "<none>"' \
  | column -t

echo ""
echo "Summary (total GPUs per type):"
kubectl get nodes -L nvidia.com/gpu.product,nvidia.com/gpu.count \
  --no-headers 2>/dev/null \
  | awk '$6 != "<none>" {gsub(/<none>/,"0",$7); gpus[$6] += $7} END {for (k in gpus) printf "  %-40s %s\n", k, gpus[k]}' \
  | sort

echo ""
echo "To use a specific GPU type, set GPU_TYPE in config.sh to the exact string above."
echo "Example: export GPU_TYPE=\"NVIDIA-RTX-A6000\""
