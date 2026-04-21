#!/usr/bin/env bash
# ============================================================================
# NRP helper. Wraps common kubectl actions for a single-user dev workflow.
# Usage: ./nrp.sh {up|sh|down|status|logs|gpu|yaml|train-submit|train-logs|train-delete}
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

K="kubectl -n ${NAMESPACE}"

# ----------------------------------------------------------------------------
# Render the interactive pod YAML from config.sh + extra PVCs
# ----------------------------------------------------------------------------
render_pod_yaml() {
  local extra_mounts=""
  local extra_volumes=""
  for entry in "${EXTRA_PVCS[@]:-}"; do
    [[ -z "$entry" ]] && continue
    IFS=':' read -r pvc path mode <<< "$entry"
    [[ -z "$pvc" || -z "$path" ]] && continue
    local readonly_flag="false"
    [[ "$mode" == "ro" ]] && readonly_flag="true"
    extra_mounts+="
    - name: ${pvc}
      mountPath: ${path}
      readOnly: ${readonly_flag}"
    extra_volumes+="
  - name: ${pvc}
    persistentVolumeClaim:
      claimName: ${pvc}"
  done

  cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${POD_NAME}
    owner: ${NRP_USER}
spec:
  restartPolicy: Never
  containers:
  - name: dev
    image: ${IMAGE}
    command: ["sleep", "infinity"]
    resources:
      requests:
        cpu: "${CPU_REQUEST}"
        memory: "${MEM_REQUEST}"
        nvidia.com/gpu: "${GPU_COUNT}"
      limits:
        cpu: "${CPU_LIMIT}"
        memory: "${MEM_LIMIT}"
        nvidia.com/gpu: "${GPU_COUNT}"
    volumeMounts:
    - name: workspace
      mountPath: ${WORKSPACE_MOUNT}
    - name: dshm
      mountPath: /dev/shm${extra_mounts}
  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
  - name: dshm
    emptyDir:
      medium: Memory
      sizeLimit: ${SHM_SIZE}${extra_volumes}
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: nvidia.com/gpu.product
            operator: In
            values:
            - ${GPU_TYPE}
EOF
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

cmd_up() {
  if $K get pod "$POD_NAME" >/dev/null 2>&1; then
    echo "✗ Pod '$POD_NAME' already exists. Either attach to it or run './nrp.sh down' first."
    $K get pod "$POD_NAME"
    exit 1
  fi

  # Sanity-check PVC exists
  if ! $K get pvc "$PVC_NAME" >/dev/null 2>&1; then
    echo "✗ PVC '$PVC_NAME' doesn't exist yet. Run ./create_pvc.sh first."
    exit 1
  fi

  echo "→ Launching pod '$POD_NAME' with ${GPU_COUNT}× ${GPU_TYPE}..."
  render_pod_yaml | kubectl apply -f -
  echo ""
  echo "→ Waiting for pod to be Ready (can take 1–3 minutes to pull the image)..."
  $K wait --for=condition=Ready "pod/$POD_NAME" --timeout=600s
  echo ""
  echo "✓ Pod is running. Scheduled on:"
  $K get pod "$POD_NAME" -o wide
  echo ""
  echo "→ GPU check:"
  $K exec "$POD_NAME" -- nvidia-smi -L
  echo ""
  echo "============================================================"
  echo "Next: attach VSCode."
  echo "  1. Open VSCode"
  echo "  2. Kubernetes tab → Workloads → Pods → right-click ${POD_NAME}"
  echo "  3. 'Attach Visual Studio Code' → open folder /workspace"
  echo ""
  echo "Or drop into a shell:  ./nrp.sh sh"
  echo "Tear down when done:   ./nrp.sh down"
  echo ""
  echo "⚠  Interactive GPU pods are auto-killed after 6 hours."
  echo "   Your PVC (${PVC_NAME}) persists. Just relaunch to continue."
  echo "============================================================"
}

cmd_sh() {
  $K exec -it "$POD_NAME" -- bash
}

cmd_down() {
  if ! $K get pod "$POD_NAME" >/dev/null 2>&1; then
    echo "Pod '$POD_NAME' doesn't exist. Nothing to do."
    return 0
  fi
  echo "→ Deleting pod '$POD_NAME'..."
  $K delete pod "$POD_NAME" --grace-period=30
  echo "✓ Pod deleted. Files on PVC '$PVC_NAME' are safe."
}

cmd_status() {
  echo "--- Pod ---"
  $K get pod "$POD_NAME" -o wide 2>/dev/null || echo "(not running)"
  echo ""
  echo "--- PVC ---"
  $K get pvc "$PVC_NAME" 2>/dev/null || echo "(not found)"
  echo ""
  echo "--- Recent events ---"
  $K get events --sort-by=.lastTimestamp 2>/dev/null | tail -10 || true
}

cmd_logs() {
  $K logs "$POD_NAME" "${@:-}"
}

cmd_gpu() {
  $K exec "$POD_NAME" -- nvidia-smi
}

cmd_yaml() {
  # Dump the rendered YAML for inspection or manual kubectl use
  render_pod_yaml
}

cmd_train_submit() {
  local job_file="${1:-}"
  if [[ -z "$job_file" ]]; then
    echo "Usage: $0 train-submit <path-to-job.yaml>" >&2
    exit 1
  fi
  if [[ ! -f "$job_file" ]]; then
    echo "File not found: $job_file" >&2
    exit 1
  fi
  # Substitute env vars in the template
  envsubst_or_sed < "$job_file" | kubectl apply -f -
}

cmd_train_logs() {
  local job_name="${1:-}"
  if [[ -z "$job_name" ]]; then
    echo "Usage: $0 train-logs <job-name>" >&2
    echo "Available jobs:"
    $K get jobs
    exit 1
  fi
  $K logs -f "job/$job_name"
}

cmd_train_delete() {
  local job_name="${1:-}"
  if [[ -z "$job_name" ]]; then
    echo "Usage: $0 train-delete <job-name>" >&2
    $K get jobs
    exit 1
  fi
  $K delete job "$job_name"
}

# Fallback substitution — works without envsubst being installed
envsubst_or_sed() {
  if command -v envsubst >/dev/null 2>&1; then
    envsubst
  else
    # Limited but dependency-free fallback for the variables we actually use
    sed \
      -e "s|\${NRP_USER}|${NRP_USER}|g" \
      -e "s|\${NAMESPACE}|${NAMESPACE}|g" \
      -e "s|\${PVC_NAME}|${PVC_NAME}|g" \
      -e "s|\${IMAGE}|${IMAGE}|g" \
      -e "s|\${GPU_TYPE}|${GPU_TYPE}|g" \
      -e "s|\${GPU_COUNT}|${GPU_COUNT}|g" \
      -e "s|\${CPU_REQUEST}|${CPU_REQUEST}|g" \
      -e "s|\${CPU_LIMIT}|${CPU_LIMIT}|g" \
      -e "s|\${MEM_REQUEST}|${MEM_REQUEST}|g" \
      -e "s|\${MEM_LIMIT}|${MEM_LIMIT}|g" \
      -e "s|\${WORKSPACE_MOUNT}|${WORKSPACE_MOUNT}|g" \
      -e "s|\${SHM_SIZE}|${SHM_SIZE}|g"
  fi
}

usage() {
  cat <<EOF
Usage: $0 <command>

Interactive pod:
  up              Launch a GPU pod with VSCode-ready environment
  sh              Shell into the running pod
  down            Delete the pod (PVC and files are preserved)
  status          Show pod + PVC + recent events
  logs [args]     Show container logs
  gpu             Run nvidia-smi inside the pod
  yaml            Print the rendered pod YAML (useful for debugging)

Training jobs:
  train-submit <file.yaml>   Submit a training Job (env vars substituted)
  train-logs   <job-name>    Follow logs from a running Job
  train-delete <job-name>    Delete a Job

Current config (from config.sh):
  User:      ${NRP_USER}
  Namespace: ${NAMESPACE}
  Pod:       ${POD_NAME}
  PVC:       ${PVC_NAME}
  GPU:       ${GPU_COUNT}× ${GPU_TYPE}
EOF
}

CMD="${1:-}"
shift || true

case "$CMD" in
  up)           cmd_up "$@" ;;
  sh|shell)     cmd_sh "$@" ;;
  down|rm)      cmd_down "$@" ;;
  status|ps)    cmd_status "$@" ;;
  logs)         cmd_logs "$@" ;;
  gpu|nvidia)   cmd_gpu "$@" ;;
  yaml)         cmd_yaml "$@" ;;
  train-submit) cmd_train_submit "$@" ;;
  train-logs)   cmd_train_logs "$@" ;;
  train-delete) cmd_train_delete "$@" ;;
  ""|help|-h|--help) usage ;;
  *) echo "Unknown command: $CMD"; echo ""; usage; exit 1 ;;
esac
