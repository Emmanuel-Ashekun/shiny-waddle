variable "project_name" { type = string  default = "edge-kube-project" }
variable "region"       { type = string  default = "us-east-1" }
variable "key_name"     { type = string  description = "Existing AWS key pair name" }
variable "edge_count"   { type = number  default = 3 }
variable "instance_type" { type = string default = "t3.small" }
variable "vpc_id"       { type = string  description = "Optional: existing VPC id"; default = "" }
variable "subnet_id"    { type = string  description = "Optional: existing subnet id"; default = "" }
variable "create_vpc"   { type = bool    default = true }

# Ubuntu 22.04 LTS amd64 (HVM) - Canonical
data "aws_ami" "ubuntu_jammy" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}