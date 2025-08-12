#!/bin/bash
set -euo pipefail

API_SERVER="https://server.kubernetes.local:6443"
CERT_AUTH="/home/ubuntu/ca.crt"
MACHINES_FILE="/home/ubuntu/machines.txt"

# Check prerequisites
echo "[+] Checking prerequisites..."
if [[ ! -f "$CERT_AUTH" ]]; then
    echo "[!] Missing CA certificate: $CERT_AUTH"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "[!] kubectl not found. Please install kubectl first."
    exit 1
fi

# Check required certificates
required_certs=("admin" "node-0" "node-1" "kube-proxy" "kube-controller-manager" "kube-scheduler")
missing_certs=()

for cert in "${required_certs[@]}"; do
    if [[ ! -f "${cert}.crt" || ! -f "${cert}.key" ]]; then
        missing_certs+=("$cert")
    fi
done

if [[ ${#missing_certs[@]} -gt 0 ]]; then
    echo "[!] Missing certificates for: ${missing_certs[*]}"
    echo "    Please run the PKI script first to generate certificates."
    exit 1
fi

echo "  All required certificates found"
echo "  kubectl is available"

# Read machines for distribution
declare -a MACHINE_IPS=()
declare -a MACHINE_HOSTS=()

if [[ -f "$MACHINES_FILE" ]]; then
    echo "  Reading machines from $MACHINES_FILE"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        fields=($line)
        MACHINE_IPS+=("${fields[0]}")
        MACHINE_HOSTS+=("${fields[2]}")
    done < "$MACHINES_FILE"
else
    echo "  ! $MACHINES_FILE not found - will use hardcoded hosts"
fi

# Generate kubeconfig function
generate_kubeconfig() {
    local component="$1"
    local user="$2"
    local server="$3"
    local cert_file="${4:-${component}.crt}"
    local key_file="${5:-${component}.key}"
    local config_file="${component}.kubeconfig"
    
    echo "[*] Generating kubeconfig for ${component}"
    
    # Set cluster
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority="${CERT_AUTH}" \
        --embed-certs=true \
        --server="${server}" \
        --kubeconfig="${config_file}"
    
    # Set credentials
    kubectl config set-credentials "${user}" \
        --client-certificate="${cert_file}" \
        --client-key="${key_file}" \
        --embed-certs=true \
        --kubeconfig="${config_file}"
    
    # Set context
    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user="${user}" \
        --kubeconfig="${config_file}"
    
    # Use context
    kubectl config use-context default \
        --kubeconfig="${config_file}"
    
    echo "  Generated ${config_file}"
}

echo -e "\n[+] Generating kubeconfigs..."

# kubelet configs for worker nodes
for host in node-0 node-1; do
    generate_kubeconfig "${host}" "system:node:${host}" "${API_SERVER}"
done

# kube-proxy
generate_kubeconfig "kube-proxy" "system:kube-proxy" "${API_SERVER}"

# kube-controller-manager
generate_kubeconfig "kube-controller-manager" "system:kube-controller-manager" "${API_SERVER}"

# kube-scheduler
generate_kubeconfig "kube-scheduler" "system:kube-scheduler" "${API_SERVER}"

# admin (uses localhost for direct access)
generate_kubeconfig "admin" "admin" "https://127.0.0.1:6443"

# Verify generated kubeconfigs
echo -e "\n[+] Verifying generated kubeconfigs..."
kubeconfigs=("node-0.kubeconfig" "node-1.kubeconfig" "kube-proxy.kubeconfig" "kube-controller-manager.kubeconfig" "kube-scheduler.kubeconfig" "admin.kubeconfig")

for config in "${kubeconfigs[@]}"; do
    if [[ -f "$config" ]]; then
        # Check if kubeconfig is valid
        if kubectl config view --kubeconfig="$config" >/dev/null 2>&1; then
            echo "  $config is valid"
        else
            echo "  $config is invalid"
        fi
    else
        echo "  $config was not created"
    fi
done

# Distribution phase
echo -e "\n[+] Distributing kubeconfigs to nodes..."

# Function to test SSH connectivity
test_ssh() {
    local host="$1"
    if ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$host" "echo 'SSH OK'" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Distribute to worker nodes
worker_nodes=("node-0" "node-1")
for host in "${worker_nodes[@]}"; do
    echo "  -> Distributing to worker node: $host"
    
    # Test SSH connectivity
    if ! test_ssh "$host"; then
        echo "    Cannot connect to root@$host - skipping"
        continue
    fi
    
    # Create directories
    if ssh root@"$host" "mkdir -p /var/lib/{kube-proxy,kubelet}"; then
        echo "    Created required directories"
    else
        echo "    Failed to create directories on $host"
        continue
    fi
    
    # Copy kube-proxy kubeconfig
    if scp kube-proxy.kubeconfig root@"$host":/var/lib/kube-proxy/kubeconfig; then
        echo "    Copied kube-proxy kubeconfig"
    else
        echo "    Failed to copy kube-proxy kubeconfig to $host"
    fi
    
    # Copy kubelet kubeconfig
    if scp "${host}.kubeconfig" root@"$host":/var/lib/kubelet/kubeconfig; then
        echo "    Copied kubelet kubeconfig"
    else
        echo "    Failed to copy kubelet kubeconfig to $host"
    fi
    
    # Set proper permissions
    ssh root@"$host" "chmod 600 /var/lib/kube-proxy/kubeconfig /var/lib/kubelet/kubeconfig" 2>/dev/null || true
    echo "    Set file permissions"
done

# Distribute to control plane
echo "  -> Distributing to control plane: server"

if ! test_ssh "server"; then
    echo "    Cannot connect to root@server - skipping control plane distribution"
else
    # Copy control plane kubeconfigs
    if scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig root@server:~/; then
        echo "    Copied control plane kubeconfigs"
        
        # Set proper permissions
        ssh root@server "chmod 600 ~/admin.kubeconfig ~/kube-controller-manager.kubeconfig ~/kube-scheduler.kubeconfig" 2>/dev/null || true
        echo "    Set file permissions"
    else
        echo "    Failed to copy control plane kubeconfigs to server"
    fi
fi

# Verification phase
echo -e "\n[+] Verifying kubeconfig distribution..."

# Verify worker nodes
for host in "${worker_nodes[@]}"; do
    echo -n "  -> $host: "
    if test_ssh "$host"; then
        if ssh root@"$host" "test -f /var/lib/kube-proxy/kubeconfig -a -f /var/lib/kubelet/kubeconfig" 2>/dev/null; then
            echo "All kubeconfigs present"
        else
            echo "Missing kubeconfigs"
        fi
    else
        echo "SSH connection failed"
    fi
done

# Verify control plane
echo -n "  -> server: "
if test_ssh "server"; then
    if ssh root@server "test -f ~/admin.kubeconfig -a -f ~/kube-controller-manager.kubeconfig -a -f ~/kube-scheduler.kubeconfig" 2>/dev/null; then
        echo "All kubeconfigs present"
    else
        echo "Missing kubeconfigs"
    fi
else
    echo "SSH connection failed"
fi

