locals {
  name = var.project_name
}

# Networking (optional: create simple VPC)
resource "aws_vpc" "this" {
  count = var.create_vpc && var.vpc_id == "" ? 1 : 0
  cidr_block = "10.42.0.0/16"
  tags = { Name = "${local.name}-vpc" }
}

resource "aws_subnet" "this" {
  count = var.create_vpc && var.subnet_id == "" ? 1 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = "10.42.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-subnet" }
}

resource "aws_internet_gateway" "this" {
  count = var.create_vpc && var.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags = { Name = "${local.name}-igw" }
}

resource "aws_route_table" "this" {
  count = var.create_vpc && var.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
  tags = { Name = "${local.name}-rt" }
}

resource "aws_route_table_association" "this" {
  count = var.create_vpc && var.subnet_id == "" ? 1 : 0
  subnet_id      = aws_subnet.this[0].id
  route_table_id = aws_route_table.this[0].id
}

# Networking inputs resolution
locals {
  vpc_id   = var.vpc_id   != "" ? var.vpc_id   : (var.create_vpc ? aws_vpc.this[0].id   : null)
  subnet_id= var.subnet_id!= "" ? var.subnet_id: (var.create_vpc ? aws_subnet.this[0].id: null)
}

# Security Group
resource "aws_security_group" "nodes" {
  name        = "${local.name}-sg"
  description = "Allow SSH, KubeEdge, and demo ports"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # KubeEdge default tunnel (CloudCore listens on 10000)
  ingress {
    from_port   = 10000
    to_port     = 10000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Demo NodePorts (30000-32767)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.name}-sg" }
}

# Central controller instance
resource "aws_instance" "central" {
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nodes.id]
  tags = { Name = "${local.name}-central" }
}

# Edge instances
resource "aws_instance" "edge" {
  count                  = var.edge_count
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nodes.id]
  tags = { Name = "${local.name}-edge-${count.index+1}" }
}