# Outputs for Ansible integration
output "jumpbox_public_ip" {
  description = "Public IP address of the jumpbox"
  value       = aws_instance.jumpbox.public_ip
}

output "jumpbox_private_ip" {
  description = "Private IP address of the jumpbox"
  value       = aws_instance.jumpbox.private_ip
}

output "server_private_ip" {
  description = "Private IP address of the server"
  value       = aws_instance.server.private_ip
}

output "node_0_private_ip" {
  description = "Private IP address of node-0"
  value       = aws_instance.nodes[0].private_ip
}

output "node_1_private_ip" {
  description = "Private IP address of node-1"
  value       = aws_instance.nodes[1].private_ip
}

# Additional useful outputs
output "all_private_ips" {
  description = "All private IP addresses"
  value = {
    jumpbox = aws_instance.jumpbox.private_ip
    server  = aws_instance.server.private_ip
    node-0  = aws_instance.nodes[0].private_ip
    node-1  = aws_instance.nodes[1].private_ip
  }
}

output "ssh_connection_commands" {
  description = "SSH connection commands"
  value = {
    jumpbox = "ssh -i ~/.ssh/your-key.pem ubuntu@${aws_instance.jumpbox.public_ip}"
    server  = "ssh -i ~/.ssh/your-key.pem ubuntu@${aws_instance.server.private_ip}"
    node-0  = "ssh -i ~/.ssh/your-key.pem ubuntu@${aws_instance.nodes[0].private_ip}"
    node-1  = "ssh -i ~/.ssh/your-key.pem ubuntu@${aws_instance.nodes[1].private_ip}"
  }
}
