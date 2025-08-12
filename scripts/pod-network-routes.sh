#!/usr/bin/env bash
set -euo pipefail

MACHINES_FILE="/home/ubuntu/machines.txt"

if [ ! -f "$MACHINES_FILE" ]; then
  echo "[ERROR] $MACHINES_FILE not found!"
  exit 1
fi

echo "[INFO] Contents of $MACHINES_FILE:"
cat "$MACHINES_FILE"
echo ""

# Parse machine info - format: "ip hostname short_name [pod_cidr]"
SERVER_IP=$(grep " server$" "$MACHINES_FILE" | awk '{print $1}')
NODE_0_IP=$(grep " node-0 " "$MACHINES_FILE" | awk '{print $1}')
NODE_0_SUBNET=$(grep " node-0 " "$MACHINES_FILE" | awk '{print $4}')
NODE_1_IP=$(grep " node-1 " "$MACHINES_FILE" | awk '{print $1}')
NODE_1_SUBNET=$(grep " node-1 " "$MACHINES_FILE" | awk '{print $4}')

# Validate parsed values
if [[ -z "$SERVER_IP" || -z "$NODE_0_IP" || -z "$NODE_0_SUBNET" || -z "$NODE_1_IP" || -z "$NODE_1_SUBNET" ]]; then
  echo "[ERROR] Failed to parse machine information from $MACHINES_FILE"
  echo "SERVER_IP: '$SERVER_IP'"
  echo "NODE_0_IP: '$NODE_0_IP'"
  echo "NODE_0_SUBNET: '$NODE_0_SUBNET'"
  echo "NODE_1_IP: '$NODE_1_IP'"
  echo "NODE_1_SUBNET: '$NODE_1_SUBNET'"
  exit 1
fi

echo "[INFO] Server IP: $SERVER_IP"
echo "[INFO] Node-0 IP: $NODE_0_IP, Pod CIDR: $NODE_0_SUBNET"
echo "[INFO] Node-1 IP: $NODE_1_IP, Pod CIDR: $NODE_1_SUBNET"

# Function to add route if not exists
add_route() {
  local host_ip=$1
  local subnet=$2
  local via_ip=$3

  echo "[INFO] Adding route $subnet via $via_ip on $host_ip"
  
  if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$host_ip" \
     "if ! ip route show | grep -q '$subnet'; then 
        ip route add $subnet via $via_ip && echo '[+] Route added successfully' || exit 1
      else 
        echo '[*] Route already exists'
      fi"; then
    echo "[✓] Route operation successful on $host_ip"
  else
    echo "[ERROR] Failed to add route on $host_ip"
    return 1
  fi
}

# Test SSH connectivity first
echo "[INFO] Testing SSH connectivity..."
for host in "$SERVER_IP" "$NODE_0_IP" "$NODE_1_IP"; do
  if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$host" "echo 'SSH test successful'" 2>/dev/null; then
    echo "[ERROR] Cannot connect to $host via SSH"
    exit 1
  fi
done

# Add routes on server
echo "[INFO] Configuring routes on server ($SERVER_IP)..."
add_route "$SERVER_IP" "$NODE_0_SUBNET" "$NODE_0_IP"
add_route "$SERVER_IP" "$NODE_1_SUBNET" "$NODE_1_IP"

# Add route on node-0
echo "[INFO] Configuring routes on node-0 ($NODE_0_IP)..."
add_route "$NODE_0_IP" "$NODE_1_SUBNET" "$NODE_1_IP"

# Add route on node-1
echo "[INFO] Configuring routes on node-1 ($NODE_1_IP)..."
add_route "$NODE_1_IP" "$NODE_0_SUBNET" "$NODE_0_IP"

echo "[✓] Pod network routes provisioning complete!"