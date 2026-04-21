# NRP Nautilus Starter Kit

A zero-to-running setup for new lab members to develop on the
[NRP Nautilus](https://nrp.ai) Kubernetes cluster with GPU + persistent storage + VSCode.

After following this, you'll have:

- `kubectl` and `kubelogin` installed and authenticated
- A personal persistent volume on Ceph (survives pod deletions, shared across your pods)
- A helper script to launch / attach / tear down GPU pods in one command
- Templates for both interactive dev (VSCode) and long-running training (Jobs)

---

## TL;DR

```bash
# 1. Edit config.sh (set your name, namespace, GPU preference)
vim config.sh

# 2. One-time install (kubectl, kubelogin, NRP config)
./install.sh

# 3. Create your personal PVC (one-time)
./create_pvc.sh

# 4. Daily: launch VSCode pod, attach, work, tear down
./nrp.sh up
# → attach VSCode via Kubernetes extension (see below)
./nrp.sh down
```

---

## One-time setup

### 1. Edit `config.sh`

The **only** file you should need to edit. Set at minimum:

```bash
export NRP_USER="yourname"          # lowercase, no spaces
export NAMESPACE="mc-lab"           # ask your advisor which namespace
export GPU_TYPE="NVIDIA-RTX-A6000"  # see list below
```

### 2. Install tools + get NRP config

```bash
./install.sh
```

This will:
- Install `kubectl` if missing (via package manager)
- Install `kubelogin` (the OIDC plugin NRP requires)
- Download `~/.kube/config` from nrp.ai
- Set your default context + namespace

You'll need to log in via CILogon in your browser on the first `kubectl` call — pick your institution (UCSD or wherever), authenticate, done. Tokens auto-refresh after that.

**Before running `install.sh`**: make sure you've already been added to a namespace on
[nrp.ai](https://nrp.ai). Ask your advisor / namespace admin to add you. Without this,
`kubectl get pods` will succeed but show nothing, and you won't be able to create pods.

### 3. Create your PVC (persistent storage)

```bash
./create_pvc.sh
```

Creates a Ceph-backed volume at `PVC_NAME` (default: `${NRP_USER}-data`) with size `PVC_SIZE`
(default: 500Gi) using `ReadWriteMany` access mode so multiple pods can mount it simultaneously
(your VSCode pod + a training Job at the same time, for example).

This PVC **persists forever**. Your pods come and go; the PVC doesn't. Anything you save under
`/workspace` inside a pod lands here.

---

## Daily workflow

### Launch a GPU pod with VSCode

```bash
./nrp.sh up
```

This:
1. Generates a pod YAML from `config.sh` + `vscode-pod.yaml`
2. Applies it to your namespace
3. Waits until the pod is `Ready`
4. Runs `nvidia-smi` to confirm the GPU is attached

### Attach VSCode

Install these VSCode extensions once:
- **Kubernetes** (`ms-kubernetes-tools.vscode-kubernetes-tools`)
- **Remote Development** (`ms-vscode-remote.vscode-remote-extensionpack`)

Then:
1. Open VSCode → click the Kubernetes icon in the left sidebar (whale + helm)
2. Bottom-left should show `nautilus / <your-namespace>` — click to confirm
3. Expand **Workloads → Pods** → right-click your pod → **Attach Visual Studio Code**
4. New VSCode window opens *inside the pod*. Open folder → `/workspace`

Your files are on Ceph. Terminal inside VSCode has CUDA, Python, PyTorch. GPU is visible:
```bash
nvidia-smi
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

### Shell into the pod (no VSCode)

```bash
./nrp.sh sh
```

### Check status

```bash
./nrp.sh status   # pod state
./nrp.sh logs     # container logs
./nrp.sh gpu      # nvidia-smi inside the pod
```

### Tear down when done

```bash
./nrp.sh down
```

**Always tear down when not using the GPU.** The cluster monitors idle pods and will
[ban namespaces with underutilized GPU requests](https://nrp.ai/documentation/userdocs/start/policies/).
Even if you forget, Nautilus auto-kills interactive GPU pods after 6 hours.

---

## Long training runs (>6 hours)

Interactive pods are killed after 6 hours. For real training runs, use a **Job** instead.
Jobs have no time limit (as long as they're doing work) and auto-clean when the command exits.

```bash
# Edit training-job.yaml to set your command, then:
./nrp.sh train-submit training-job.yaml
./nrp.sh train-logs my-training-job
./nrp.sh train-delete my-training-job
```

Your Job mounts the same PVC, so `/workspace` has the same files as your VSCode pod.
Develop in VSCode → commit a working `train.py` → submit it as a Job → watch it from your laptop.

⚠️ **Never run `sleep` or any command that never ends inside a Job**. That gets your account
banned. Jobs are for commands that actually finish.

---

## Useful commands cheatsheet

```bash
# What pods do I have running?
kubectl get pods

# What PVCs?
kubectl get pvc

# Describe a stuck pod (shows scheduling errors, OOM, etc.)
kubectl describe pod <pod-name>

# See available GPU types in the cluster
./list_gpus.sh

# See which nodes have A6000s and how many are free
kubectl get nodes -L nvidia.com/gpu.product | grep A6000

# Free storage usage
kubectl exec <pod-name> -- df -h /workspace

# Nuke everything in your namespace (be careful!)
kubectl delete pods --all
kubectl delete jobs --all
```

---

## Common GPU types to set in `config.sh`

```
NVIDIA-GeForce-RTX-3090          # 24GB, plentiful
NVIDIA-GeForce-RTX-4090          # 24GB, newer
NVIDIA-RTX-A6000                 # 48GB, great for training
NVIDIA-L40                       # 48GB, newer datacenter card
NVIDIA-A100-SXM4-80GB            # 80GB, high-demand
NVIDIA-A100-SXM4-40GB            # 40GB
NVIDIA-H100-80GB-HBM3            # 80GB, very high-demand
```

Run `./list_gpus.sh` to see what's currently in the cluster and which are available to your namespace.

---

## Where to get help

- **Matrix**: All NRP support happens in [Matrix](https://matrix.nrp-nautilus.io). Join the
  `#general` and `#support` rooms. Response time is usually under an hour during business hours.
- **Docs**: [nrp.ai/documentation](https://nrp.ai/documentation/)
- **Cluster policies** (READ THIS): [nrp.ai/documentation/userdocs/start/policies](https://nrp.ai/documentation/userdocs/start/policies/)
- **Troubleshooting**: see [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) in this kit

---

## What's in this kit

```
nrp-starter/
├── README.md                    # This file
├── TROUBLESHOOTING.md           # Common errors and fixes
├── config.sh                    # ← EDIT THIS ONE
├── install.sh                   # One-time setup (kubectl + kubelogin + config)
├── create_pvc.sh                # Create your personal PVC
├── nrp.sh                       # Main helper (up / sh / down / train-submit / etc.)
├── list_gpus.sh                 # List available GPU types in cluster
├── vscode-pod.yaml              # Interactive dev pod template
└── training-job.yaml            # Long-running training Job template
```
