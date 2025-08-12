#!/usr/bin/env bash
set -euo pipefail

echo "[+] Creating generic secret..."
kubectl create secret generic kubernetes-the-hard-way --from-literal="mykey=mydata" --dry-run=client -o yaml | kubectl apply -f -

echo "[+] Secret created. Fetching encrypted secret from etcd..."

ETCD_SERVER="server" 

ssh root@"$ETCD_SERVER" "etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C" | tee /tmp/encrypted-secret.hex

echo "[+] Check that etcd key contains 'k8s:enc:aescbc:v1:key1' indicating encryption."
if grep -q "k8s:enc:aescbc:v1:key1" /tmp/encrypted-secret.hex; then
  echo "Secret is encrypted at rest."
else
  echo "Secret encryption verification failed."
fi

echo "[+] Creating nginx deployment..."
kubectl create deployment nginx --image=nginx:latest --dry-run=client -o yaml | kubectl apply -f -

echo "[+] Waiting for nginx pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=nginx --timeout=120s

POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")
echo "[+] Nginx pod: $POD_NAME"

# Start port-forward in background and save PID
kubectl port-forward "$POD_NAME" 8087:80 >/tmp/portforward.log 2>&1 &
PF_PID=$!

# Wait for port-forward to be ready (poll or sleep)
for i in {1..15}; do
  if curl --silent --head http://127.0.0.1:8087 >/dev/null 2>&1; then
    echo "Port-forward is up"
    break
  fi
  sleep 1
done

if ! curl --silent --head http://127.0.0.1:8087 >/dev/null 2>&1; then
  echo "Port-forward never started correctly"
  kill $PF_PID || true
  exit 1
fi

# Run your curl test
curl -I http://127.0.0.1:8087

# Kill port-forward process after test
kill $PF_PID
wait $PF_PID 2>/dev/null || true



echo "[+] Printing nginx pod logs..."
kubectl logs "$POD_NAME"

echo "[+] Executing 'nginx -v' inside the pod..."
kubectl exec -ti "$POD_NAME" -- nginx -v

echo "[+] Exposing nginx deployment as NodePort service..."
kubectl expose deployment nginx --port=80 --type=NodePort --dry-run=client -o yaml | kubectl apply -f -

NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
NODE_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].spec.nodeName}")

echo "[+] NodePort for nginx service: $NODE_PORT"
echo "[+] Node running nginx pod: $NODE_NAME"

echo "[+] Testing access to nginx service via NodePort..."

curl -I http://"$NODE_NAME":"$NODE_PORT"

echo "Kubernetes smoke test completed successfully!"
