# Troubleshooting

Common errors and their fixes, in rough order of how often they hit new users.

---

## `unauthorized_client: unknown+client` or `failed to refresh token`

Your `kubelogin` plugin is missing or broken, or your cached token is stale.

**Fix:**
```bash
# Make sure kubelogin is installed and on PATH
which kubectl-oidc_login
# If empty, re-run install.sh — kubelogin install is step one.

# Clear stale cached token
kubectl oidc-login clean

# Re-download config (auth flow rebuilds from scratch)
curl -o ~/.kube/config -fSL "https://nrp.ai/config"
chmod 600 ~/.kube/config
kubectl config use-context nautilus
kubectl config set-context --current --namespace=<your-namespace>

# Trigger fresh browser login
kubectl get pods
```

---

## `kubectl get pods` says "No resources found" but I expected to see stuff

This is actually fine — it just means *you* haven't created any pods yet. The command
succeeded. You can now create pods.

If instead you get `forbidden` or `cannot list resource`, you haven't been added to the
namespace. Ask your advisor / namespace admin to add you at https://nrp.ai/namespaces.

---

## Pod stuck in `Pending`

```bash
kubectl describe pod <pod-name>
```

Look at the **Events** section at the bottom. Common causes:

| Event | Fix |
|---|---|
| `0/N nodes are available: N Insufficient nvidia.com/gpu` | That GPU type is fully booked. Wait, or change `GPU_TYPE` in config.sh to something less contested (RTX-3090, L40). |
| `pod has unbound immediate PersistentVolumeClaims` | Your PVC isn't bound yet. `kubectl get pvc` — if it shows `Pending`, the storage class might be wrong. |
| `didn't match Pod's node affinity/selector` | Your `GPU_TYPE` doesn't match any node label. Run `./list_gpus.sh` for exact names. |
| `Insufficient cpu` / `Insufficient memory` | Lower `CPU_REQUEST` / `MEM_REQUEST` in config.sh. |
| `exceeded quota` | Your namespace is at its cap. Check `kubectl describe resourcequota` and delete idle pods. |

---

## `Multi-Attach error for volume ... Volume is already exclusively attached`

You're trying to mount a `ReadWriteOnce` (RWO) PVC on a new pod while another pod still holds it.

**Fix:** either delete the old pod (`kubectl get pods` → find the culprit → `kubectl delete pod <name>`),
or recreate the PVC as `ReadWriteMany` (RWX) if your storage class supports it. RWX is what
`rook-cephfs-*` provides — RWO is `rook-ceph-block`.

---

## Pod is `Running` but `kubectl exec` hangs or fails

Usually the container is still pulling (first launch with a big image can take 2–5 minutes)
or crashlooping.

```bash
kubectl get pod <pod-name> -o wide   # check STATUS and RESTARTS
kubectl logs <pod-name>              # see why the container died
kubectl describe pod <pod-name>      # see pull progress or crash events
```

---

## `nvidia-smi: command not found` inside the pod

You picked a base image that doesn't have the NVIDIA userspace libraries. Stick with the
default `gitlab-registry.nrp-nautilus.io/prp/jupyter-stack/prp:latest`, or any image
that has CUDA preinstalled (`nvcr.io/nvidia/*`, `pytorch/pytorch:*-cuda*`).

You can still run GPU code — the kernel driver is mounted from the host — but most images
expect `nvidia-smi` to exist for sanity checks.

---

## `torch.cuda.is_available()` returns `False` in the pod

Check the resource request actually included a GPU:
```bash
./nrp.sh yaml | grep -A2 nvidia.com/gpu
```
Should show `nvidia.com/gpu: "1"` (or more). If `GPU_COUNT=0` you get a CPU-only pod.

Also make sure you're not inside a `conda` env that installed a CPU-only torch build:
```bash
pip show torch | grep -i cuda
```
Reinstall with `pip install torch --index-url https://download.pytorch.org/whl/cu121` if needed.

---

## VSCode "Attach" doesn't show up or fails

Two common causes:

1. **`kubectl` or `kubectl-oidc_login` not on PATH** as seen by VSCode. VSCode inherits PATH
   from wherever it was launched. If you installed to `~/.local/bin` but VSCode can't find them,
   either relaunch VSCode from a terminal where PATH is set, or symlink the binaries to a
   directory that's always on PATH (`/usr/local/bin`).

2. **VSCode is using a different kubeconfig.** It must read from `~/.kube/config` — not a
   custom path. If you've been using `export KUBECONFIG=...` for something else, that will
   break it. Unset that env var and relaunch.

The official NRP docs on this:
https://nrp.ai/documentation/userdocs/start/getting-started/#visual-studio-code

---

## My pod got killed / I lost my work

**Interactive pods with a GPU are auto-killed after 6 hours.** This is expected — your PVC
(code, checkpoints, data) is safe. Just `./nrp.sh up` again.

For anything longer than 6h, use a Job (`./nrp.sh train-submit`) instead.

---

## I'm getting warnings about "utilization violations"

You requested more resources than you're actually using. Nautilus monitors this, and
[will ban namespaces that consistently over-request](https://nrp.ai/documentation/userdocs/start/policies/).

**Fix:** lower `CPU_REQUEST`, `MEM_REQUEST`, and especially `GPU_COUNT` in config.sh
to match what you actually use. Rule of thumb: request what you need on average, set
limits a bit above your peak.

You can check your current utilization at https://nrp.ai/namespaces → click your namespace → Violations tab.

---

## I need to mount a shared lab dataset

Add it to `EXTRA_PVCS` in config.sh:

```bash
export EXTRA_PVCS=(
  "siggraphasia20dataset:/data/siggraphasia20:ro"
  "openroomsindepthaosu:/data/openrooms:ro"
)
```

Format is `pvc-name:mount-path:mode`. `ro` = read-only (safer for shared datasets), `rw`
= read-write. Restart the pod for changes to take effect (`./nrp.sh down && ./nrp.sh up`).

To see what shared PVCs exist in your namespace: `kubectl get pvc`.

---

## Something else broke

- Ask in the [NRP Matrix](https://matrix.nrp-nautilus.io) `#support` room — very responsive.
- Search the [NRP docs](https://nrp.ai/documentation/).
- Include the output of `kubectl describe pod <pod-name>` when asking for help.
