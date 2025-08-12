#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_KEY="/home/ubuntu/ec2-key.pem"
JUMPBOX_KEY="$HOME/.ssh/id_rsa"
HOSTS_FILE="/etc/hosts"
MACHINES_FILE="/home/ubuntu/machines.txt"

# Check if machines.txt exists and is readable
if [ ! -f "$MACHINES_FILE" ]; then
    echo "[ERROR] $MACHINES_FILE not found!"
    exit 1
fi

echo "[DEBUG] Contents of $MACHINES_FILE:"
cat "$MACHINES_FILE"
echo "[DEBUG] End of file"

# Read all machines into arrays first 
declare -a MACHINE_FQDNS=()
declare -a MACHINE_HOSTS=()
declare -a MACHINE_SUBNETS=()

echo "[+] Reading machines from file..."
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    fields=($line)
    MACHINE_IPS+=("${fields[0]}")
    MACHINE_FQDNS+=("${fields[1]}")
    MACHINE_HOSTS+=("${fields[2]}")
    MACHINE_SUBNETS+=("${fields[3]:-}")
    echo "[DEBUG] Added machine: ${fields[2]} (${fields[0]})"
done < "$MACHINES_FILE"

total_machines=${#MACHINE_IPS[@]}
echo "[INFO] Found $total_machines machines to process:"
for i in "${!MACHINE_HOSTS[@]}"; do
    echo "  $((i+1)). ${MACHINE_HOSTS[i]} (${MACHINE_IPS[i]})"
done

if [ "$total_machines" -eq 0 ]; then
    echo "[ERROR] No machines found!"
    exit 1
fi

# Generate jumpbox key if missing
if [ ! -f "$JUMPBOX_KEY" ]; then
    echo "[+] Generating new SSH key for jumpbox..."
    ssh-keygen -t rsa -b 2048 -f "$JUMPBOX_KEY" -N ""
else
    echo "[+] Jumpbox key already exists at $JUMPBOX_KEY"
fi

# Add hostnames to /etc/hosts
echo -e "\n[+] Updating /etc/hosts with machine hostnames..."
for i in "${!MACHINE_HOSTS[@]}"; do
    IP="${MACHINE_IPS[i]}"
    FQDN="${MACHINE_FQDNS[i]}"
    HOST="${MACHINE_HOSTS[i]}"
    
    if ! grep -q "$HOST" "$HOSTS_FILE"; then
        echo "$IP $FQDN $HOST" | sudo tee -a "$HOSTS_FILE" >/dev/null
        echo "[+] Added $HOST ($IP) to /etc/hosts"
    else
        echo "[+] $HOST already in /etc/hosts"
    fi
done

# Process each machine
echo -e "\n[+] Distributing jumpbox public key to nodes, enabling root SSH, and setting hostnames..."
processed_count=0
# Prepare all hosts entries for cluster
HOSTS_ENTRIES=""
for i in "${!MACHINE_HOSTS[@]}"; do
  IP="${MACHINE_IPS[i]}"
  FQDN="${MACHINE_FQDNS[i]}"
  HOST="${MACHINE_HOSTS[i]}"
  HOSTS_ENTRIES+="$IP $FQDN $HOST\n"
done


for i in "${!MACHINE_HOSTS[@]}"; do
    IP="${MACHINE_IPS[i]}"
    FQDN="${MACHINE_FQDNS[i]}"
    HOST="${MACHINE_HOSTS[i]}"
    
    processed_count=$((processed_count + 1))
    echo -e "\n[*] Processing machine $processed_count/$total_machines: $HOST ($IP)..."

    # Copy key to ubuntu user
    echo "  -> Adding key to ubuntu@$HOST..."
    if ssh -i "$BOOTSTRAP_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 "ubuntu@$IP" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys" \
        < "$JUMPBOX_KEY.pub"; then
        echo "  Key added to ubuntu@$HOST"
    else
        echo "  Failed to add key to ubuntu@$HOST"
        continue
    fi

    # Setup root SSH access with proper permissions
    echo "  -> Setting up root SSH access on $HOST..."
    if ssh -i "$BOOTSTRAP_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 "ubuntu@$IP" \
        "sudo mkdir -p /root/.ssh && \
         sudo chmod 700 /root/.ssh && \
         sudo touch /root/.ssh/authorized_keys && \
         sudo chmod 600 /root/.ssh/authorized_keys && \
         sudo chown root:root /root/.ssh/authorized_keys && \
         sudo bash -c 'cat >> /root/.ssh/authorized_keys'" \
         < "$JUMPBOX_KEY.pub"; then
        echo "  Key added to root@$HOST"
    else
        echo "  Failed to add key to root@$HOST"
        continue
    fi

    # Enable PermitRootLogin and restart SSH
    echo "  -> Configuring SSH daemon on $HOST..."
    if ssh -i "$BOOTSTRAP_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 "ubuntu@$IP" \
        "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
         sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
         sudo systemctl restart ssh"; then
        echo "  SSH configured on $HOST"
    else
        echo "  Failed to configure SSH on $HOST"
        continue
    fi

    # Wait for SSH to restart
    echo "  -> Waiting for SSH restart..."
    sleep 3

    # Verify key was added correctly
    echo "  -> Verifying key installation on $HOST..."
    KEY_FINGERPRINT=$(ssh-keygen -lf "$JUMPBOX_KEY.pub" | awk '{print $2}')
    if ssh -i "$BOOTSTRAP_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "ubuntu@$IP" "sudo ssh-keygen -lf /root/.ssh/authorized_keys | grep -q '$KEY_FINGERPRINT'"; then
        echo "  Key verified on $HOST"
    else
        echo "  Key verification failed on $HOST (but may still work)"
    fi

    # Set hostname and update remote /etc/hosts
    echo "  -> Setting hostname on $HOST..."
    if ssh -i "$BOOTSTRAP_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 "ubuntu@$IP" \
        "sudo hostnamectl set-hostname $HOST && \
         grep -q '$HOST' /etc/hosts || echo '$IP $FQDN $HOST' | sudo tee -a /etc/hosts >/dev/null"; then
        echo "  Hostname configured on $HOST"
    else
        echo "  Failed to set hostname on $HOST"
    fi

    echo "  -> Updating /etc/hosts on $HOST with full cluster hosts entries..."
    ssh -i "$BOOTSTRAP_KEY" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=30 "ubuntu@$IP" bash -c "'
        set -e
        echo -e \"$HOSTS_ENTRIES\" | while read -r line; do
            host_ip=\$(echo \$line | awk \"{print \$1}\")
            host_name=\$(echo \$line | awk \"{print \$3}\")
            if ! grep -q \"\$host_name\" /etc/hosts; then
                echo \$line | sudo tee -a /etc/hosts >/dev/null
            fi
        done
    '"
    echo "  ✓ /etc/hosts updated on $HOST"

    echo "[+] Completed processing $HOST"
    echo "========================================"
done

echo "[INFO] Processed $processed_count total machines"

# Preload SSH known_hosts to avoid prompts
echo -e "\n[+] Preloading SSH known_hosts..."
for i in "${!MACHINE_HOSTS[@]}"; do
    IP="${MACHINE_IPS[i]}"
    HOST="${MACHINE_HOSTS[i]}"
    
    echo "  -> Adding $HOST to known_hosts..."
    ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true
done

# Verify passwordless SSH access (ubuntu and root)
echo -e "\n[+] Verifying SSH access..."
echo "========================================"
for i in "${!MACHINE_HOSTS[@]}"; do
    HOST="${MACHINE_HOSTS[i]}"

    echo -n "[*] ubuntu@$HOST: "
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ubuntu@$HOST" hostname >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi

    echo -n "[*] root@$HOST: "
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$HOST" hostname >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi
done

echo -e "\n[+] SSH key distribution, root access configuration, and hostname setup completed!"
echo "[INFO] Summary: Successfully processed $processed_count machines"
for i in "${!MACHINE_HOSTS[@]}"; do
    echo "      - ${MACHINE_HOSTS[i]} (${MACHINE_IPS[i]})"
done