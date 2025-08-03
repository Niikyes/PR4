output "ec2_public_ip" {
  value = aws_eip.pr4_eip.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.pr4_rds.address
}


