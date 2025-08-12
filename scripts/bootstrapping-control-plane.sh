#!/usr/bin/env bash

set -euo pipefail

CONTROLLERS=("server") 
BIN_SRC_DIR="/home/ubuntu/kubernetes-the-hard-way/downloads"
UNIT_SRC_DIR="/home/ubuntu/kubernetes-the-hard-way/units"
CONFIG_SRC_DIR="/home/ubuntu/kubernetes-the-hard-way/configs"


for host in "${CONTROLLERS[@]}"; do
  echo "[*] Copying Kubernetes control plane binaries, configs, and unit files to $host"

  scp \
    "$BIN_SRC_DIR/controller/kube-apiserver" \
    "$BIN_SRC_DIR/controller/kube-controller-manager" \
    "$BIN_SRC_DIR/controller/kube-scheduler" \
    "$BIN_SRC_DIR/client/kubectl" \
    "$UNIT_SRC_DIR/kube-apiserver.service" \
    "$UNIT_SRC_DIR/kube-controller-manager.service" \
    "$UNIT_SRC_DIR/kube-scheduler.service" \
    "$CONFIG_SRC_DIR/kube-scheduler.yaml" \
    "$CONFIG_SRC_DIR/kube-apiserver-to-kubelet.yaml" \
    root@"$host":~/
done


for host in "${CONTROLLERS[@]}"; do
  echo "[*] Installing and configuring control plane on $host"

  ssh root@"$host" bash -s <<'EOF'
set -e

echo "[*] Creating config directories"
mkdir -p /etc/kubernetes/config /var/lib/kubernetes

echo "[*] Moving binaries to /usr/local/bin"
mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

echo "[*] Moving certs and encryption config"
mv ca.crt ca.key \
   kube-api-server.key kube-api-server.crt \
   service-accounts.key service-accounts.crt \
   encryption-config.yaml /var/lib/kubernetes/

echo "[*] Moving kubeconfigs"
mv kube-controller-manager.kubeconfig /var/lib/kubernetes/ || true
mv kube-scheduler.kubeconfig /var/lib/kubernetes/ || true

echo "[*] Moving config files"
mv kube-scheduler.yaml /etc/kubernetes/config/

echo "[*] Moving systemd unit files"
mv kube-apiserver.service /etc/systemd/system/
mv kube-controller-manager.service /etc/systemd/system/
mv kube-scheduler.service /etc/systemd/system/

echo "[*] Reloading systemd and starting services"
systemctl daemon-reload
systemctl enable kube-apiserver kube-controller-manager kube-scheduler
systemctl start kube-apiserver kube-controller-manager kube-scheduler

echo "[*] Waiting for API server to start..."
sleep 10

echo "[*] Checking service statuses"
systemctl status kube-apiserver --no-pager
EOF
done


for host in "${CONTROLLERS[@]}"; do
  echo "[*] Applying RBAC for kube-apiserver-to-kubelet on $host"
  ssh root@"$host" "kubectl apply -f kube-apiserver-to-kubelet.yaml --kubeconfig admin.kubeconfig"
done


for host in "${CONTROLLERS[@]}"; do
  echo "[*] Verifying control plane on $host"
  ssh root@"$host" "kubectl cluster-info --kubeconfig admin.kubeconfig"
done

echo "[✓] Kubernetes control plane bootstrap completed successfully"
