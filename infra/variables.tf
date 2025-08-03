variable "region" {
  default = "us-east-1"
}

variable "ami_id" {
  description = "AMI Ubuntu 22.04 LTS en us-east-1"
  default     = "ami-053a45fff0a704a47"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "db_name" {
  default = "test"
}

variable "db_username" {
  default = "postgres"
}

variable "db_password" {
  description = "Contraseña del usuario maestro de PostgreSQL"
  default     = "12345678"
  sensitive   = true
}
