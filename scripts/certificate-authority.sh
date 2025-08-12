#!/usr/bin/env bash
set -euo pipefail

CA_CONF="/home/ubuntu/kubernetes-the-hard-way/ca.conf"
DAYS_VALID=3653
MACHINES_FILE="/home/ubuntu/machines.txt"

if [[ ! -f "$CA_CONF" ]]; then
  echo "[!] Missing $CA_CONF. Please create it before running."
  exit 1
fi

if [[ ! -f "$MACHINES_FILE" ]]; then
  echo "[!] Missing $MACHINES_FILE. Please create it before running."
  exit 1
fi

echo "[+] Reading machines from $MACHINES_FILE..."
declare -a MACHINE_IPS=()
declare -a MACHINE_FQDNS=()
declare -a MACHINE_HOSTS=()
declare -a MACHINE_SUBNETS=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  
  fields=($line)
  MACHINE_IPS+=("${fields[0]}")
  MACHINE_FQDNS+=("${fields[1]}")
  MACHINE_HOSTS+=("${fields[2]}")
  MACHINE_SUBNETS+=("${fields[3]:-}")
  echo "  - ${fields[2]} (${fields[0]})"
done < "$MACHINES_FILE"

total_machines=${#MACHINE_IPS[@]}
echo "[INFO] Found $total_machines machines"

echo -e "\n[+] Generating CA private key and self-signed certificate..."
if [[ ! -f ca.key || ! -f ca.crt ]]; then
  echo "  -> Generating CA private key (4096-bit RSA)..."
  openssl genrsa -out ca.key 4096
  
  echo "  -> Generating self-signed CA certificate..."
  openssl req -x509 -new -sha512 -noenc \
    -key ca.key -days "$DAYS_VALID" \
    -config "$CA_CONF" \
    -out ca.crt
  
  echo "  CA certificate generated (valid for $DAYS_VALID days)"
else
  echo "  CA already exists (ca.key, ca.crt)"
fi

certs=(
  "admin" "node-0" "node-1"
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "kube-api-server"
  "service-accounts"
)

echo -e "\n[+] Generating component certificates..."
for i in "${certs[@]}"; do
  if [[ ! -f "$i.key" || ! -f "$i.crt" ]]; then
    echo "  -> Generating certificate for: $i"
    
    openssl genrsa -out "${i}.key" 4096
    
    openssl req -new -key "${i}.key" -sha256 \
      -config "$CA_CONF" -section "${i}" \
      -out "${i}.csr"
    
    openssl x509 -req -days "$DAYS_VALID" -in "${i}.csr" \
      -copy_extensions copyall \
      -sha256 -CA "ca.crt" \
      -CAkey "ca.key" \
      -CAcreateserial \
      -out "${i}.crt"
    
    rm -f "${i}.csr"
    
    echo "    ${i}.key and ${i}.crt generated"
  else
    echo "  $i certificate already exists"
  fi
done

# Verify certificates were created
echo -e "\n[+] Certificate generation summary:"
for i in "${certs[@]}"; do
  if [[ -f "$i.key" && -f "$i.crt" ]]; then
    echo "   $i"
  else
    echo "  $i (MISSING)"
  fi
done

# Distribute certificates to nodes
echo -e "\n[+] Distributing certificates to nodes..."

for i in "${!MACHINE_HOSTS[@]}"; do
  IP="${MACHINE_IPS[i]}"
  HOST="${MACHINE_HOSTS[i]}"
  
  case "$HOST" in
    node-0|node-1)
      echo "  -> Distributing to worker node: $HOST ($IP)"
      
      # Test SSH connectivity first
      if ! ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
        echo "    Cannot connect to root@$HOST - skipping"
        continue
      fi
      
      # Create kubelet directory
      if ssh root@"$HOST" "mkdir -p /var/lib/kubelet/"; then
        echo "    Created /var/lib/kubelet/ directory"
      else
        echo "    Failed to create directory on $HOST"
        continue
      fi
      
      # Copy CA certificate
      if scp ca.crt root@"$HOST":/var/lib/kubelet/; then
        echo "    Copied CA certificate"
      else
        echo "    Failed to copy CA certificate to $HOST"
        continue
      fi
      
      # Copy node certificate
      if scp "${HOST}.crt" root@"$HOST":/var/lib/kubelet/kubelet.crt; then
        echo "    Copied node certificate"
      else
        echo "    Failed to copy node certificate to $HOST"
        continue
      fi
      
      # Copy node private key
      if scp "${HOST}.key" root@"$HOST":/var/lib/kubelet/kubelet.key; then
        echo "    Copied node private key"
      else
        echo "    Failed to copy node private key to $HOST"
        continue
      fi
      
      # Set proper permissions
      ssh root@"$HOST" "chmod 600 /var/lib/kubelet/kubelet.key && chmod 644 /var/lib/kubelet/kubelet.crt /var/lib/kubelet/ca.crt"
      echo "    Set file permissions"
      ;;
      
    server)
      echo "  -> Distributing to control plane: $HOST ($IP)"
      
      # Test SSH connectivity first
      if ! ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
        echo "    Cannot connect to root@$HOST - skipping"
        continue
      fi
      
      # Copy control plane certificates
      if scp \
        ca.key ca.crt \
        kube-api-server.key kube-api-server.crt \
        service-accounts.key service-accounts.crt \
        root@"$HOST":~/; then
        echo "    Copied control plane certificates"
        
        # Set proper permissions
        ssh root@"$HOST" "chmod 600 ~/ca.key ~/kube-api-server.key ~/service-accounts.key && chmod 644 ~/ca.crt ~/kube-api-server.crt ~/service-accounts.crt"
        echo "    Set file permissions"
      else
        echo "    Failed to copy certificates to $HOST"
      fi
      ;;
      
    *)
      echo "  -> Unknown host type: $HOST - skipping"
      ;;
  esac
done

# Verify distribution
echo -e "\n[+] Verifying certificate distribution..."
for i in "${!MACHINE_HOSTS[@]}"; do
  HOST="${MACHINE_HOSTS[i]}"
  
  case "$HOST" in
    node-0|node-1)
      echo -n "  -> $HOST: "
      if ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$HOST" \
        "test -f /var/lib/kubelet/ca.crt -a -f /var/lib/kubelet/kubelet.crt -a -f /var/lib/kubelet/kubelet.key" 2>/dev/null; then
        echo "All certificates present"
      else
        echo "Missing certificates"
      fi
      ;;
    server)
      echo -n "  -> $HOST: "
      if ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$HOST" \
        "test -f ~/ca.key -a -f ~/ca.crt -a -f ~/kube-api-server.key -a -f ~/kube-api-server.crt -a -f ~/service-accounts.key -a -f ~/service-accounts.crt" 2>/dev/null; then
        echo "All certificates present"
      else
        echo "Missing certificates"
      fi
      ;;
  esac
done

