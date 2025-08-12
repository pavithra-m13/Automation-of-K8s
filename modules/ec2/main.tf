resource "aws_instance" "jumpbox" {
  ami                    = var.ami_id
  instance_type          = var.jumpbox_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.sg_id]
  key_name               = var.key_name

  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }

  tags = {
    Name = "jumpbox"
  }

  provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/setup-jumpbox.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = self.public_ip
      private_key = file(var.private_key_path)
    }
  }
}

resource "aws_instance" "server" {
  ami                         = var.ami_id
  instance_type               = var.server_instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.sg_id]
  key_name                    = var.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "server"
  }
}

resource "aws_instance" "nodes" {
  count                       = 2
  ami                         = var.ami_id
  instance_type               = var.node_instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.sg_id]
  key_name                    = var.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "node-${count.index}"
  }
}

resource "null_resource" "setup_hosts" {
  provisioner "remote-exec" {
    inline = [
      for line in split("\n", trimspace(templatefile("/mnt/c/k8s/scripts/setup.sh", {
        server_ip = aws_instance.server.private_ip,
        node0_ip  = aws_instance.nodes[0].private_ip,
        node1_ip  = aws_instance.nodes[1].private_ip
      }))) : line if trimspace(line) != ""
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }

  depends_on = [
    aws_instance.jumpbox,
    aws_instance.server,
    aws_instance.nodes
  ]
}


resource "null_resource" "setup_ssh" {
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/ubuntu/ec2-key.pem"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/ubuntu/ec2-key.pem"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }

  provisioner "file" {
    source      = "/mnt/c/k8s/scripts/setup-ssh.sh"
    destination = "/home/ubuntu/setup-ssh.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/setup-ssh.sh",
      "bash /home/ubuntu/setup-ssh.sh"
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }

  depends_on = [
    null_resource.setup_hosts
  ]
}

resource "null_resource" "certificate_authority" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/certificate-authority.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.setup_ssh
  ]
}

resource "null_resource" "kubernetes_configuration" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/configuration-file.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.certificate_authority
  ]
}

resource "null_resource" "encryption-key" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/encryption-key.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.kubernetes_configuration
  ]
}


resource "null_resource" "etcd" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/bootstrapping-etcd.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.encryption-key
  ]
}


resource "null_resource" "control_plane" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/bootstrapping-control-plane.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.etcd
  ]
}

resource "null_resource" "worker_plane" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/bootstrapping-workers.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.control_plane
  ]
}
resource "null_resource" "configure_kubectl" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/configure-kubectl.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.worker_plane
  ]
}
resource "null_resource" "pod_network_route" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/pod-network-routes.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.configure_kubectl
  ]
}

resource "null_resource" "smoke_test" {
    provisioner "remote-exec" {
    script = "/mnt/c/k8s/scripts/smoke-test.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_instance.jumpbox.public_ip
      private_key = file(var.private_key_path)
    }
  }
  
  depends_on = [
    null_resource.pod_network_route
  ]
}