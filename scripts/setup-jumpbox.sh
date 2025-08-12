#!/bin/bash
set -euxo pipefail

# Update and install packages
sudo apt-get update -y
sudo apt-get install -y wget curl vim openssl git tar

# Set up the working directory
cd /home/ubuntu
sudo chown -R ubuntu:ubuntu /home/ubuntu

# Run as ubuntu user
sudo -u ubuntu bash <<'EOSU'
cd ~
git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git
cd kubernetes-the-hard-way
ARCH=$(dpkg --print-architecture)

mkdir -p downloads/{client,cni-plugins,controller,worker}
wget -q --show-progress --https-only --timestamping -P downloads -i downloads-${ARCH}.txt

tar -xvf downloads/crictl-v*.tar.gz -C downloads/worker/
tar -xvf downloads/containerd-*.tar.gz --strip-components 1 -C downloads/worker/
tar -xvf downloads/cni-plugins-linux-${ARCH}-v*.tgz -C downloads/cni-plugins/
tar -xvf downloads/etcd-v3.6.0-rc.3-linux-${ARCH}.tar.gz -C downloads/ --strip-components=1 etcd-v3.6.0-rc.3-linux-${ARCH}/etcd etcd-v3.6.0-rc.3-linux-${ARCH}/etcdctl

mv downloads/{etcdctl,kubectl} downloads/client/ || true
mv downloads/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} downloads/controller/ || true
mv downloads/{kubelet,kube-proxy} downloads/worker/ || true
mv downloads/runc.${ARCH} downloads/worker/runc || true

chmod +x downloads/{client,cni-plugins,controller,worker}/* || true
echo "Setup complete"
EOSU

# Move kubectl to /usr/local/bin
sudo cp /home/ubuntu/kubernetes-the-hard-way/downloads/client/kubectl /usr/local/bin/ || true
