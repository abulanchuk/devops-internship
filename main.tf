terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region     = "eu-central-1"
  shared_credentials_files = ["C:\\Users\\anaumovich\\.aws\\credentials"]
}

// To Generate Private Key
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

variable "ubuntu_setup_script" {
  default = <<-EOF
#!/bin/bash
apt-get update && \
apt-get install nginx ca-certificates curl -y && \
systemctl start nginx && \
systemctl enable nginx && \
# Add Docker's official GPG key:
install -m 0755 -d /etc/apt/keyrings && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
chmod a+r /etc/apt/keyrings/docker.asc && \
# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null && \
apt-get update && \
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y && \
systemctl start docker && \
cp /home/ubuntu/index.html /var/www/html/index.nginx-debian.html
EOF
}

variable "key_name" {
  description = "The name of the file to store the private key"
  type        = string
  default     = "ssh_key.pem"
}

// Create Key Pair for Connecting EC2 via SSH
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

// Save PEM file locally
resource "local_sensitive_file" "private_key" {
  content  = tls_private_key.rsa_4096.private_key_pem
  filename = var.key_name
}

# Create a VPC
resource "aws_vpc" "main_vpc" {
  enable_dns_hostnames = true
  cidr_block           = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route" "route" {
  route_table_id         = aws_vpc.main_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# Create a Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Create a Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "private-subnet"
  }
}

# Create a security group
resource "aws_security_group" "sg_ec2" {
  vpc_id      = aws_vpc.main_vpc.id
  name        = "sg_ec2"
  description = "Security group for EC2"

  # Allow incoming ICMP (ping)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ubuntu_server" {
  ami = "ami-0084a47cc718c111a"  # Ubuntu
  instance_type = "t2.micro"

  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.sg_ec2.id]
  associate_public_ip_address = true

  user_data = var.ubuntu_setup_script
  key_name  = aws_key_pair.key_pair.key_name
  tags = {
    Name = "Ubuntu-EC2"
  }
}

resource "aws_instance" "linux_server" {
  ami = "ami-0592c673f0b1e7665"  # Amazon Linux
  instance_type = "t2.micro"

  subnet_id                   = aws_subnet.private_subnet.id
  vpc_security_group_ids      = [aws_security_group.sg_ec2.id]
  associate_public_ip_address = false

  tags = {
    Name = "Linux-EC2"
  }
}

# Output the public IP of the EC2 instance
output "instance_public_ip" {
  value = aws_instance.ubuntu_server.public_ip
}