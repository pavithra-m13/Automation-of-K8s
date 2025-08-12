output "jumpbox_ip" {
  value = aws_instance.jumpbox.public_ip
}
output "jumpbox_private_ip" {
  value = aws_instance.jumpbox.private_ip
}
output "server_ip" {
  value = aws_instance.server.public_ip
}

output "node_ips" {
  value = aws_instance.nodes[*].public_ip
}


output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "nodes_private_ip" {
  value = aws_instance.nodes[*].private_ip
}


