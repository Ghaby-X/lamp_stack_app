# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# Web Tier Outputs
output "web_instance_public_ip" {
  description = "Public IP of web server"
  value       = module.web_instance.public_ip
}

output "web_instance_public_dns" {
  description = "Public DNS of web server"
  value       = module.web_instance.public_dns
}

# App Tier Outputs
output "app_instance_id" {
  description = "App instance ID"
  value       = module.app_instance.id
}

output "app_instance_private_ip" {
  description = "Private IP of app server"
  value       = module.app_instance.private_ip
}

# Database Tier Outputs
output "db_instance_id" {
  description = "Database instance ID"
  value       = module.db_instance.id
}

output "db_instance_private_ip" {
  description = "Private IP of database server"
  value       = module.db_instance.private_ip
}

# Security Group Outputs
output "web_security_group_id" {
  description = "Web security group ID"
  value       = module.web_security_group.security_group_id
}

output "app_security_group_id" {
  description = "App security group ID"
  value       = module.app_security_group.security_group_id
}

output "db_security_group_id" {
  description = "Database security group ID"
  value       = module.db_security_group.security_group_id
}

# Key Pair Output
output "key_pair_name" {
  description = "Name of the key pair"
  value       = aws_key_pair.main.key_name
}

output "private_key_file" {
  description = "Path to private key file"
  value       = "${path.module}/${local.name}_key.pem"
}