resource "tls_private_key" "mykey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.mykey.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.mykey.private_key_pem
  filename = "${path.module}/${var.key_name}.pem"
  file_permission = "400"
}

module "vpc"{
    source  = "./modules/vpc"
    vpc_cidr           = var.vpc_cidr          
    public_subnet_cidr = var.public_subnet_cidr
}

module "ec2"{
    source = "./modules/ec2"
    subnet_id = module.vpc.subnet_id
    sg_id= module.vpc.sg_id
    ami_id = var.ami_id
    key_name               = aws_key_pair.generated_key.key_name  
    jumpbox_instance_type = "t2.micro"
    server_instance_type = "t2.small"
    node_instance_type = "t2.small"
  private_key_path = "/mnt/c/k8s/keypair.pem"

}