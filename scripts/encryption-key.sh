#!/bin/bash
set -euo pipefail

# 1. Generate encryption key
echo "[*] Generating ENCRYPTION_KEY"
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# 2. Create encryption-config.yaml from template
TEMPLATE="/home/ubuntu/kubernetes-the-hard-way/configs/encryption-config.yaml"
OUTPUT="encryption-config.yaml"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "[!] Template $TEMPLATE not found!"
  exit 1
fi

echo "[*] Creating $OUTPUT from $TEMPLATE"
envsubst < "$TEMPLATE" > "$OUTPUT"

# 3. Distribute to controller nodes
CONTROLLERS=("server") 

for host in "${CONTROLLERS[@]}"; do
  echo "[*] Copying encryption-config.yaml to $host"
  scp "$OUTPUT" root@"$host":/var/lib/kubernetes/encryption-config.yaml
done


echo "[✓] Encryption config created and distributed successfully"
