output "jumpbox_public_ip" {
  description = "Public IP address of the jumpbox"
  value       = module.ec2.jumpbox_ip
}

output "jumpbox_private_ip" {
  description = "Private IP address of the jumpbox"
  value       = module.ec2.jumpbox_private_ip
}

output "server_private_ip" {
  description = "Private IP address of the server"
  value       = module.ec2.server_private_ip
}

output "node_private_ips" {
  description = "Private IP addresses of the nodes"
  value       = module.ec2.nodes_private_ip
}

# output "ssh_connection_command" {
#   description = "Command to SSH into the jumpbox"
#   value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.jumpbox.public_ip}"
# }
