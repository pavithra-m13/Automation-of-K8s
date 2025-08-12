#!/usr/bin/env bash

set -euo pipefail

CONTROLLERS=("server")  
BIN_SRC_DIR="/home/ubuntu/kubernetes-the-hard-way/downloads"
UNIT_SRC="/home/ubuntu/kubernetes-the-hard-way/units/etcd.service"

for host in "${CONTROLLERS[@]}"; do
  echo "[*] Copying etcd binaries and service file to $host"
  scp "$BIN_SRC_DIR/controller/etcd" \
      "$BIN_SRC_DIR/client/etcdctl" \
      "$UNIT_SRC" \
      root@"$host":~/
done

for host in "${CONTROLLERS[@]}"; do
  echo "[*] Installing and configuring etcd on $host"
  
  ssh root@"$host" bash -s <<'EOF'
set -e
echo "[*] Moving binaries to /usr/local/bin"
mv etcd etcdctl /usr/local/bin/

echo "[*] Creating etcd directories"
mkdir -p /etc/etcd /var/lib/etcd
chmod 700 /var/lib/etcd

echo "[*] Copying certs"
cp ca.crt kube-api-server.key kube-api-server.crt /etc/etcd/

echo "[*] Moving systemd unit file"
mv etcd.service /etc/systemd/system/

echo "[*] Reloading systemd and starting etcd"
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd

echo "[*] etcd status:"
systemctl status etcd --no-pager
EOF
done


for host in "${CONTROLLERS[@]}"; do
  echo "[*] Verifying etcd on $host"
  ssh root@"$host" "etcdctl member list"
done

echo "[✓] etcd bootstrap completed successfully"
