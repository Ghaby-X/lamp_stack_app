# ================================
# TIER 3: Database Layer
# ================================
module "db_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                   = "${local.name}_db"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.main.key_name
  monitoring             = true
  subnet_id              = module.vpc.database_subnets[0]
  vpc_security_group_ids = [module.db_security_group.security_group_id]

  user_data = <<EOF
#!/bin/bash
set -e

# Update system and install Docker
dnf update -y
dnf install -y docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group (optional, for easier docker use)
usermod -aG docker ec2-user

# Create docker volume for MySQL data
docker volume create mysql_data

# Run MySQL container with volume and env vars
docker run -d \
  --name mysql-server \
  -e MYSQL_ROOT_PASSWORD=${var.database_password} \
  -e MYSQL_DATABASE=${var.database_name} \
  -p 3306:3306 \
  -v mysql_data:/var/lib/mysql \
  --restart unless-stopped \
  mysql:8

# Wait for MySQL to initialize
echo "Waiting 30 seconds for MySQL to initialize..."
sleep 30

# Create table and insert initial row inside container
docker exec -i mysql-server mysql -u root -p${var.database_password} <<EOF
USE appdb;
CREATE TABLE IF NOT EXISTS counters (
  id INT PRIMARY KEY,
  count INT DEFAULT 0
);
INSERT INTO counters (id, count) VALUES (1, 0) ON DUPLICATE KEY UPDATE count=count;
EOF


  tags = {
    Terraform   = "true"
    Environment = "dev"
    Tier        = "database"
  }
}


# db security group
module "db_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}_db_sg"
  description = "Database security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "MySQL from app tier"
      source_security_group_id = module.app_security_group.security_group_id
    }
  ]

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}