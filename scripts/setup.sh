echo "${server_ip} server.kubernetes.local server" | sudo tee -a /etc/hosts
echo "${node0_ip} node-0.kubernetes.local node-0 10.200.0.0/24" | sudo tee -a /etc/hosts
echo "${node1_ip} node-1.kubernetes.local node-1 10.200.1.0/24" | sudo tee -a /etc/hosts


# Create a machines.txt file in user's home
cat <<EOF > /home/ubuntu/machines.txt
${server_ip} server.kubernetes.local server
${node0_ip} node-0.kubernetes.local node-0 10.200.0.0/24
${node1_ip} node-1.kubernetes.local node-1 10.200.1.0/24
EOF

# Set permissions
chown ubuntu:ubuntu /home/ubuntu/machines.txt
chmod 644 /home/ubuntu/machines.txt