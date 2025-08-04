provider "aws" {
  region = var.region
}

# =========================================================
# 0. Limpieza previa total
# =========================================================
resource "null_resource" "aws_cleanup" {
  provisioner "local-exec" {
    command = <<EOT
      echo "🗑️ Eliminando EC2 existentes..."
      EC2S=$(aws ec2 describe-instances --query "Reservations[].Instances[].InstanceId" --output text)
      for EC2 in $EC2S; do
        aws ec2 terminate-instances --instance-ids $EC2 || true
        aws ec2 wait instance-terminated --instance-ids $EC2 || true
      done

      echo "🗑️ Eliminando RDS existentes..."
      DBS=$(aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text)
      for DB in $DBS; do
        aws rds delete-db-instance --db-instance-identifier $DB --skip-final-snapshot || true
        aws rds wait db-instance-deleted --db-instance-identifier $DB || true
      done

      echo "🗑️ Eliminando DB Subnet Groups..."
      DB_SUBNETS=$(aws rds describe-db-subnet-groups --query "DBSubnetGroups[].DBSubnetGroupName" --output text)
      for DBSUB in $DB_SUBNETS; do
        aws rds delete-db-subnet-group --db-subnet-group-name $DBSUB || true
      done

      echo "🗑️ Liberando Elastic IPs (EIPs)..."
      EIPS=$(aws ec2 describe-addresses --query "Addresses[].AllocationId" --output text)
      for EIP in $EIPS; do
        aws ec2 release-address --allocation-id $EIP || true
      done

      echo "🗑️ Eliminando interfaces de red (ENIs)..."
      ENIS=$(aws ec2 describe-network-interfaces --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
      for ENI in $ENIS; do
        aws ec2 delete-network-interface --network-interface-id $ENI || true
      done

      echo "🗑️ Eliminando KeyPairs duplicadas..."
      aws ec2 delete-key-pair --key-name pr4-key || true

      echo "🗑️ Eliminando VPCs..."
      VPCS=$(aws ec2 describe-vpcs --query "Vpcs[].VpcId" --output text)
      for VPC in $VPCS; do
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query "Subnets[].SubnetId" --output text)
        for SUB in $SUBNETS; do aws ec2 delete-subnet --subnet-id $SUB || true; done

        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query "InternetGateways[].InternetGatewayId" --output text)
        for GW in $IGWS; do
          aws ec2 detach-internet-gateway --internet-gateway-id $GW --vpc-id $VPC || true
          aws ec2 delete-internet-gateway --internet-gateway-id $GW || true
        done

        RTBS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" --query "RouteTables[].RouteTableId" --output text)
        for RTB in $RTBS; do
          MAIN=$(aws ec2 describe-route-tables --route-table-ids $RTB --query "RouteTables[].Associations[].Main" --output text)
          if [[ "$MAIN" != "True" ]]; then aws ec2 delete-route-table --route-table-id $RTB || true; fi
        done

        SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
        for SG in $SGS; do aws ec2 delete-security-group --group-id $SG || true; done

        aws ec2 delete-vpc --vpc-id $VPC || true
      done
    EOT
  }
}

# =========================================================
# 1. KeyPair
# =========================================================
resource "tls_private_key" "pr4_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "pr4_key" {
  key_name   = "pr4-key"
  public_key = tls_private_key.pr4_key.public_key_openssh
  lifecycle { ignore_changes = [public_key] }
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
}

resource "aws_internet_gateway" "pr4_igw" {
  vpc_id = aws_vpc.pr4_vpc.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.pr4_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.pr4_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.pr4_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.pr4_vpc.id
  route { cidr_block = "0.0.0.0/0" gateway_id = aws_internet_gateway.pr4_igw.id }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# =========================================================
# 3. Security Groups
# =========================================================
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.pr4_vpc.id

  ingress { from_port=22 to_port=22 protocol="tcp" cidr_blocks=["0.0.0.0/0"] }
  ingress { from_port=80 to_port=80 protocol="tcp" cidr_blocks=["0.0.0.0/0"] }
  ingress { from_port=8080 to_port=8080 protocol="tcp" cidr_blocks=["0.0.0.0/0"] }
  egress  { from_port=0 to_port=0 protocol="-1" cidr_blocks=["0.0.0.0/0"] }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.pr4_vpc.id
  ingress { from_port=5432 to_port=5432 protocol="tcp" security_groups=[aws_security_group.ec2_sg.id] }
  egress  { from_port=0 to_port=0 protocol="-1" cidr_blocks=["0.0.0.0/0"] }
}

# =========================================================
# 4. EC2
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
    systemctl enable docker && systemctl start docker
  EOF
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











