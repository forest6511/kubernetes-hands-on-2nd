#!/usr/bin/env bash
# GitHub Actions（Ubuntu）に、本書と同じ版の minikube・kubectl・Helm を入れる
#   bash scripts/ci-install-tools.sh minikube kubectl helm
set -euo pipefail
MINIKUBE_VERSION=${MINIKUBE_VERSION:-v1.39.0}
KUBECTL_VERSION=${KUBECTL_VERSION:-v1.37.1}
HELM_VERSION=${HELM_VERSION:-v4.3.1}
tmp=$(mktemp -d)
for tool in "$@"; do
  case $tool in
    minikube)
      curl -fsSLo "$tmp/minikube" \
        "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64"
      sudo install "$tmp/minikube" /usr/local/bin/minikube ;;
    kubectl)
      curl -fsSLo "$tmp/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
      sudo install "$tmp/kubectl" /usr/local/bin/kubectl ;;
    helm)
      curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C "$tmp"
      sudo install "$tmp/linux-amd64/helm" /usr/local/bin/helm ;;
    *) echo "unknown tool: $tool" >&2; exit 1 ;;
  esac
done
