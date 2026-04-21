#!/usr/bin/env bash
# ============================================================================
# NRP Nautilus one-time setup.
# Installs kubectl, kubelogin, downloads the cluster config, and sets context.
# Safe to re-run: skips steps that are already done.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

OS="$(uname -s)"
ARCH="$(uname -m)"

# Normalize architecture
case "$ARCH" in
  x86_64|amd64)  GOARCH="amd64" ;;
  arm64|aarch64) GOARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

case "$OS" in
  Darwin) GOOS="darwin" ;;
  Linux)  GOOS="linux"  ;;
  *) echo "Unsupported OS: $OS (Windows users: use WSL)" >&2; exit 1 ;;
esac

INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "NOTE: $INSTALL_DIR is not in your PATH."
  echo "Add this to your ~/.zshrc or ~/.bashrc:"
  echo ""
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
  export PATH="$INSTALL_DIR:$PATH"
fi

# ---------- kubectl ----------
if command -v kubectl >/dev/null 2>&1; then
  echo "✓ kubectl already installed: $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')"
else
  echo "→ Installing kubectl..."
  KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL -o "$INSTALL_DIR/kubectl" \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${GOOS}/${GOARCH}/kubectl"
  chmod +x "$INSTALL_DIR/kubectl"
  if [[ "$OS" == "Darwin" ]]; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/kubectl" 2>/dev/null || true
  fi
  echo "✓ kubectl installed at $INSTALL_DIR/kubectl"
fi

# ---------- kubelogin ----------
# NRP requires the kubelogin plugin for OIDC/CILogon auth.
# It must be reachable on PATH as "kubectl-oidc_login" (note the underscore).
if command -v kubectl-oidc_login >/dev/null 2>&1; then
  echo "✓ kubelogin plugin already installed"
else
  echo "→ Installing kubelogin..."
  KUBELOGIN_VERSION="$(curl -fsSL "https://api.github.com/repos/int128/kubelogin/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
  TMPDIR="$(mktemp -d)"
  cd "$TMPDIR"
  curl -fsSL -o kubelogin.zip \
    "https://github.com/int128/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin_${GOOS}_${GOARCH}.zip"
  unzip -q kubelogin.zip
  # Binary is named "kubelogin" inside the zip on some platforms, or in a subdir
  BIN_PATH="$(find . -name 'kubelogin' -type f | head -1)"
  [[ -z "$BIN_PATH" ]] && { echo "Could not find kubelogin binary in zip" >&2; exit 1; }
  mv "$BIN_PATH" "$INSTALL_DIR/kubectl-oidc_login"
  chmod +x "$INSTALL_DIR/kubectl-oidc_login"
  if [[ "$OS" == "Darwin" ]]; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/kubectl-oidc_login" 2>/dev/null || true
  fi
  cd "$SCRIPT_DIR"
  rm -rf "$TMPDIR"
  echo "✓ kubelogin installed at $INSTALL_DIR/kubectl-oidc_login"
fi

# ---------- NRP kubeconfig ----------
KUBE_CONFIG="${HOME}/.kube/config"
mkdir -p "${HOME}/.kube"

if [[ -f "$KUBE_CONFIG" ]] && kubectl config get-contexts nautilus >/dev/null 2>&1; then
  echo "✓ NRP config already present at $KUBE_CONFIG"
  read -r -p "Redownload it? [y/N] " REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    cp "$KUBE_CONFIG" "${KUBE_CONFIG}.bak.$(date +%s)"
    curl -fsSL -o "$KUBE_CONFIG" "https://nrp.ai/config"
    chmod 600 "$KUBE_CONFIG"
    echo "✓ NRP config refreshed (old one backed up)"
  fi
else
  echo "→ Downloading NRP kubeconfig..."
  if [[ -f "$KUBE_CONFIG" ]]; then
    cp "$KUBE_CONFIG" "${KUBE_CONFIG}.bak.$(date +%s)"
    echo "  (backed up existing ~/.kube/config)"
  fi
  curl -fsSL -o "$KUBE_CONFIG" "https://nrp.ai/config"
  chmod 600 "$KUBE_CONFIG"
  echo "✓ Config downloaded to $KUBE_CONFIG"
fi

# ---------- Set context + namespace ----------
kubectl config use-context nautilus >/dev/null
kubectl config set-context --current --namespace="$NAMESPACE" >/dev/null
echo "✓ Default context: nautilus"
echo "✓ Default namespace: $NAMESPACE"

# ---------- Test auth ----------
echo ""
echo "→ Testing cluster access (this will open a browser for CILogon login the first time)..."
echo ""
if kubectl get pods 2>&1 | tee /tmp/nrp-auth-test.log; then
  echo ""
  echo "============================================================"
  echo "✓ ALL SET. You're authenticated with NRP Nautilus."
  echo ""
  echo "Next steps:"
  echo "  1. Create your personal PVC:  ./create_pvc.sh"
  echo "  2. Launch a GPU pod:          ./nrp.sh up"
  echo "============================================================"
else
  echo ""
  echo "============================================================"
  echo "✗ Auth test failed. See TROUBLESHOOTING.md for common fixes."
  echo "  Most common cause: you haven't been added to a namespace."
  echo "  Ask your advisor to add you at https://nrp.ai/namespaces"
  echo "============================================================"
  exit 1
fi
