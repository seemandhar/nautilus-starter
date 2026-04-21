#!/usr/bin/env bash
# ============================================================================
# NRP Nautilus config — EDIT THIS FILE BEFORE RUNNING ANYTHING ELSE.
# All other scripts source this file.
# ============================================================================

# -------- Identity --------
# Your username. Used as a prefix for pod/job/PVC names.
# Lowercase letters, numbers, and dashes only. No spaces, no underscores.
export NRP_USER="yourname"

# The Kubernetes namespace your advisor/admin added you to.
# Check by visiting https://nrp.ai → User → Namespaces.
export NAMESPACE="mc-lab"

# -------- Persistent storage (PVC) --------
# Name of your personal PVC. Default: "${NRP_USER}-data".
# This volume persists across pods — your code and checkpoints live here.
export PVC_NAME="${NRP_USER}-data"
export PVC_SIZE="500Gi"

# Storage class options (run `kubectl get sc` to list what's available):
#   rook-cephfs-haosu   ← RWX, shared lab storage (mc-lab uses this)
#   rook-cephfs-central ← RWX, central Ceph
#   rook-cephfs         ← RWX, generic
#   rook-ceph-block     ← RWO, faster but single-pod mount only
export PVC_STORAGE_CLASS="rook-cephfs-haosu"

# ReadWriteMany (RWX) lets multiple pods mount the same PVC simultaneously.
# ReadWriteOnce (RWO) is faster but only one pod at a time.
# RWX is strongly recommended for development — run VSCode + training at once.
export PVC_ACCESS_MODE="ReadWriteMany"

# -------- GPU selection --------
# Run ./list_gpus.sh to see what's available. Common values:
#   NVIDIA-GeForce-RTX-3090        (24GB, plentiful)
#   NVIDIA-GeForce-RTX-4090        (24GB)
#   NVIDIA-RTX-A6000               (48GB, recommended for most training)
#   NVIDIA-L40                     (48GB)
#   NVIDIA-A100-SXM4-40GB          (40GB, high-demand)
#   NVIDIA-A100-SXM4-80GB          (80GB, high-demand)
#   NVIDIA-H100-80GB-HBM3          (80GB, very high-demand)
export GPU_TYPE="NVIDIA-RTX-A6000"
export GPU_COUNT="1"

# -------- CPU + memory --------
# Requests = guaranteed. Limits = max before throttling/OOM-kill.
# Keep requests realistic — the cluster bans namespaces with over-requested
# but under-used resources. Start small, scale up if monitoring shows you need it.
export CPU_REQUEST="4"
export CPU_LIMIT="8"
export MEM_REQUEST="32Gi"
export MEM_LIMIT="64Gi"

# -------- Container image --------
# The base image. Has CUDA + Python + PyTorch + Jupyter preinstalled.
# Other good options:
#   nvcr.io/nvidia/pytorch:24.08-py3   (NVIDIA's optimized PyTorch)
#   pytorch/pytorch:2.4.0-cuda12.1-cudnn9-devel
#   tensorflow/tensorflow:latest-gpu
# You can also build your own and push to gitlab-registry.nrp-nautilus.io.
export IMAGE="gitlab-registry.nrp-nautilus.io/prp/jupyter-stack/prp:latest"

# -------- Pod naming --------
export POD_NAME="${NRP_USER}-vscode"

# -------- Optional: extra PVCs to mount (shared datasets) --------
# Format: "pvc-name:/mount/path:ro" (ro = read-only, rw = read-write)
# Leave empty to skip. Example for mc-lab members:
#
#   export EXTRA_PVCS=(
#     "openroomsindepthaosu:/data/openrooms:ro"
#     "siggraphasia20dataset:/data/siggraphasia20:ro"
#   )
export EXTRA_PVCS=()

# ============================================================================
# Below this line: internal defaults. Don't usually need to change.
# ============================================================================

# Workspace mount path inside the pod
export WORKSPACE_MOUNT="/workspace"

# Shared memory size (/dev/shm) — PyTorch DataLoaders need ≥8Gi typically
export SHM_SIZE="16Gi"

# Validate required fields
if [[ "$NRP_USER" == "yourname" ]]; then
  echo "ERROR: You haven't set NRP_USER in config.sh yet." >&2
  echo "       Open config.sh and change the NRP_USER line." >&2
  return 1 2>/dev/null || exit 1
fi
