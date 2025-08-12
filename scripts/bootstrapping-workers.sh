#!/usr/bin/env bash
set -euo pipefail

WORKERS=("node-0" "node-1")  
BIN_SRC_DIR="/home/ubuntu/kubernetes-the-hard-way/downloads"
CONFIGS_DIR="/home/ubuntu/kubernetes-the-hard-way/configs"
UNITS_DIR="/home/ubuntu/kubernetes-the-hard-way/units"
CNI_DIR="$BIN_SRC_DIR/cni-plugins"

for HOST in "${WORKERS[@]}"; do
  echo "[*] Preparing configs for $HOST"
  SUBNET=$(grep "$HOST" machines.txt | cut -d " " -f 4)

  sed "s|SUBNET|$SUBNET|g" "$CONFIGS_DIR/10-bridge.conf" > 10-bridge.conf
  sed "s|SUBNET|$SUBNET|g" "$CONFIGS_DIR/kubelet-config.yaml" > kubelet-config.yaml

  echo "[*] Copying configs to $HOST"
  scp 10-bridge.conf kubelet-config.yaml \
      root@"$HOST":~/
done

for HOST in "${WORKERS[@]}"; do
  echo "[*] Copying binaries & unit files to $HOST"
  scp \
    "$BIN_SRC_DIR/worker/"* \
    "$BIN_SRC_DIR/client/kubectl" \
    "$CONFIGS_DIR/99-loopback.conf" \
    "$CONFIGS_DIR/containerd-config.toml" \
    "$CONFIGS_DIR/kube-proxy-config.yaml" \
    "$UNITS_DIR/containerd.service" \
    "$UNITS_DIR/kubelet.service" \
    "$UNITS_DIR/kube-proxy.service" \
    root@"$HOST":~/
  
  echo "[*] Copying CNI plugins to $HOST"
  ssh root@"$HOST" "mkdir -p ~/cni-plugins"
  scp "$CNI_DIR"/* root@"$HOST":~/cni-plugins/
done


for HOST in "${WORKERS[@]}"; do
  echo "[*] Bootstrapping worker node $HOST"
  
  ssh root@"$HOST" bash -s <<'EOF'
set -e

echo "[*] Installing OS dependencies"
apt-get update -y
apt-get install -y socat conntrack ipset kmod

echo "[*] Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "[*] Creating directories"
mkdir -p /etc/cni/net.d /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes

echo "[*] Installing worker binaries"
mv crictl kube-proxy kubelet runc /usr/local/bin/
mv containerd containerd-shim-runc-v2 containerd-stress /bin/
mv cni-plugins/* /opt/cni/bin/

echo "[*] Configuring CNI networking"
mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/
modprobe br-netfilter
echo "br-netfilter" >> /etc/modules-load.d/modules.conf
cat <<SYSCTL > /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL
sysctl -p /etc/sysctl.d/kubernetes.conf

echo "[*] Configuring containerd"
mkdir -p /etc/containerd/
mv containerd-config.toml /etc/containerd/config.toml
mv containerd.service /etc/systemd/system/

echo "[*] Configuring kubelet"
mv kubelet-config.yaml /var/lib/kubelet/
mv kubelet.service /etc/systemd/system/

echo "[*] Configuring kube-proxy"
mv kube-proxy-config.yaml /var/lib/kube-proxy/
mv kube-proxy.service /etc/systemd/system/

echo "[*] Starting worker services"
systemctl daemon-reload
systemctl enable containerd kubelet kube-proxy
systemctl start containerd kubelet kube-proxy

echo "[✓] Worker node bootstrap complete"
EOF
done

echo "[✓] All worker nodes bootstrapped successfully"
