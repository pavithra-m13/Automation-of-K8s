#!/usr/bin/env bash
set -euo pipefail

# Variables - adjust paths if needed
CERT_DIR="/home/ubuntu"
KUBECONFIG_FILE="$HOME/.kube/config"
API_SERVER="https://server.kubernetes.local:6443"
CLUSTER_NAME="kubernetes-the-hard-way"
USER_NAME="admin"
CONTEXT_NAME="kubernetes-the-hard-way"

# Create .kube directory if not exists
mkdir -p "$(dirname "$KUBECONFIG_FILE")"

echo "[+] Generating kubeconfig file for admin user..."

kubectl config set-cluster "$CLUSTER_NAME" \
  --certificate-authority="$CERT_DIR/ca.crt" \
  --embed-certs=true \
  --server="$API_SERVER" \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config set-credentials "$USER_NAME" \
  --client-certificate="$CERT_DIR/admin.crt" \
  --client-key="$CERT_DIR/admin.key" \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config set-context "$CONTEXT_NAME" \
  --cluster="$CLUSTER_NAME" \
  --user="$USER_NAME" \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config use-context "$CONTEXT_NAME" --kubeconfig="$KUBECONFIG_FILE"

echo "[+] kubeconfig file generated at $KUBECONFIG_FILE"

echo "[+] Verifying kubectl connectivity to the cluster..."

kubectl version --kubeconfig="$KUBECONFIG_FILE"
kubectl get nodes --kubeconfig="$KUBECONFIG_FILE"
