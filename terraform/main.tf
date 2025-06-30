locals {
  name    = "lamp_stack"
  db_name = "lamp_db"
}

# ================================
# KEY PAIR
# ================================
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "main" {
  key_name   = "${local.name}_key"
  public_key = tls_private_key.main.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.main.private_key_pem
  filename = "${path.module}/${local.name}_key.pem"
  file_permission = "0600"
}

# ================================
# VPC MODULE
# ================================
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                        = "${local.name}_vpc"
  cidr                        = "10.0.0.0/16"
  map_public_ip_on_launch     = true
  azs                         = ["eu-west-1a", "eu-west-1b"]
  public_subnets              = ["10.0.101.0/24", "10.0.103.0/24"]
  private_subnets             = ["10.0.1.0/24", "10.0.2.0/24"]
  database_subnets            = ["10.0.201.0/24", "10.0.202.0/24"]
  enable_nat_gateway          = true
  create_database_subnet_group = true

  public_subnet_tags = {
    "map_public_ip_on_launch" = "true"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# ================================
# TIER 1: Web Layer (Frontend)
# ================================
module "web_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                          = "${local.name}_web"
  instance_type                 = "t2.micro"
  key_name                      = aws_key_pair.main.key_name
  monitoring                    = true
  subnet_id                     = module.vpc.public_subnets[0]
  associate_public_ip_address   = true
  vpc_security_group_ids        = [module.web_security_group.security_group_id]

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y httpd php
systemctl start httpd
systemctl enable httpd

cat > /var/www/html/index.php << 'EOL'
<?php
$app_server = "${module.app_instance.private_ip}:3000";

// Get current count from app tier
$count = file_get_contents("http://$app_server/count");
?>
<!DOCTYPE html>
<html>
<head><title>Page Visit Counter</title></head>
<body>
    <h1>Page Visit Counter</h1>
    <h2>This page has been visited <?= $count ?> times</h2>
    <p><a href="/">Refresh to increment counter</a></p>
</body>
</html>
EOL
EOF

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Tier        = "web"
  }
}

# ================================
# TIER 2: App Layer (API)
# ================================
module "app_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                   = "${local.name}_app"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.main.key_name
  monitoring             = true
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.app_security_group.security_group_id]

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y httpd php php-mysqlnd
systemctl start httpd
systemctl enable httpd

# Create the API endpoint
cat > /var/www/html/api.php << 'EOL'
<?php
header('Content-Type: text/plain');

$host = "${module.db_instance.private_ip}";
$user = "admin";
$password = "password123";
$database = "appdb";

try {
    $pdo = new PDO("mysql:host=$host;dbname=$database", $user, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // Increment counter
    $pdo->exec("UPDATE counters SET count = count + 1 WHERE id = 1");

    // Fetch updated count
    $stmt = $pdo->query("SELECT count FROM counters WHERE id = 1");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    echo $row['count'];
} catch (PDOException $e) {
    echo "0";
}
?>
EOL
EOF


  tags = {
    Terraform   = "true"
    Environment = "dev"
    Tier        = "app"
  }
}

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
yum update -y
yum install -y mysql-server
systemctl start mysqld
systemctl enable mysqld

mysql -e "CREATE DATABASE appdb;"
mysql -e "CREATE USER 'admin'@'%' IDENTIFIED BY 'password123';"
mysql -e "GRANT ALL PRIVILEGES ON appdb.* TO 'admin'@'%';"
mysql -e "FLUSH PRIVILEGES;"

mysql -e "USE appdb; CREATE TABLE counters (
  id INT PRIMARY KEY,
  count INT DEFAULT 0
);"

mysql -e "USE appdb; INSERT INTO counters (id, count) VALUES (1, 0);"
EOF

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Tier        = "database"
  }
}

# ================================
# SECURITY GROUPS
# ================================
module "web_security_group" {
  source  = "terraform-aws-modules/security-group/aws"

  name        = "${local.name}_web_sg"
  description = "Web server security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws"

  name        = "${local.name}_app_sg"
  description = "App server security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 3000
      to_port                  = 3000
      protocol                 = "tcp"
      description              = "App access from web tier"
      source_security_group_id = module.web_security_group.security_group_id
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

  egress_rules = ["all-all"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
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