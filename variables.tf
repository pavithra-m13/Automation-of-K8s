variable "region" {
  default = "us-east-2"
}

variable "vpc_cidr" {
  default = "10.100.0.0/16"
}

variable "public_subnet_cidr" {
  default = "10.100.1.0/24"
}

variable "ami_id" {
  default = "ami-0d1b5a8c13042c939" # Ubuntu 22.04 LTS
}

variable "key_name" {
  default = "keypair"
}
