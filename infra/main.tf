provider "aws" {
  region = var.region
}

# =========================================================
# 0. Limpieza previa (RDS y VPC existentes)
# =========================================================
data "aws_vpcs" "existing" {}
resource "null_resource" "delete_old_vpcs" {
  provisioner "local-exec" {
    command = <<EOT
      for vpc in $(aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text); do
        echo "Deleting VPC $vpc..."
        aws ec2 delete-vpc --vpc-id $vpc || true
      done
    EOT
  }
}

resource "null_resource" "delete_old_rds" {
  provisioner "local-exec" {
    command = <<EOT
      for db in $(aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text); do
        echo "Deleting RDS $db..."
        aws rds delete-db-instance --db-instance-identifier $db --skip-final-snapshot || true
      done
    EOT
  }
}

# =========================================================
# 1. Generar clave SSH
# =========================================================
resource "tls_private_key" "pr4_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "pr4_key" {
  key_name   = "pr4-key"
  public_key = tls_private_key.pr4_key.public_key_openssh
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [public_key]
  }
}

resource "local_file" "pr4_private_key" {
  content  = tls_private_key.pr4_key.private_key_pem
  filename = "${path.module}/pr4-key.pem"
}

# =========================================================
# 2. VPC y Red
# =========================================================
resource "aws_vpc" "pr4_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "pr4-vpc" }
  lifecycle { create_before_destroy = true }
}

resource "aws_internet_gateway" "pr4_igw" {
  vpc_id = aws_vpc.pr4_vpc.id
  tags   = { Name = "pr4-igw" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.pr4_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "pr4-public-subnet" }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.pr4_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "pr4-private-subnet-a" }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.pr4_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "pr4-private-subnet-b" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.pr4_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pr4_igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# =========================================================
# 3. Security Groups
# =========================================================
resource "aws_security_group" "ec2_sg" {
  name   = "pr4-ec2-sg"
  vpc_id = aws_vpc.pr4_vpc.id

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
    from_port   = 8080
    to_port     = 8080
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

resource "aws_security_group" "rds_sg" {
  name   = "pr4-rds-sg"
  vpc_id = aws_vpc.pr4_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =========================================================
# 4. EC2 Instance
# =========================================================
resource "aws_instance" "pr4_ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = aws_key_pair.pr4_key.key_name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose postgresql-client
    systemctl start docker
    systemctl enable docker
  EOF

  tags = { Name = "pr4-ec2" }
}

resource "aws_eip" "pr4_eip" {
  instance = aws_instance.pr4_ec2.id
}

# =========================================================
# 5. RDS PostgreSQL
# =========================================================
resource "aws_db_subnet_group" "pr4_db_subnet" {
  name       = "pr4-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}

resource "aws_db_instance" "pr4_rds" {
  identifier             = "pr4-postgres"
  engine                 = "postgres"
  engine_version         = "17.4"
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  db_name                = var.db_name
  allocated_storage      = 20
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.pr4_db_subnet.name
  publicly_accessible    = false
}

# =========================================================
# Outputs
# =========================================================
output "ec2_public_ip" {
  value = aws_eip.pr4_eip.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.pr4_rds.address
}





