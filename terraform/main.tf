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
$app_server = "${module.app_instance.private_ip}";

// Get count from app tier
$response = file_get_contents("http://$app_server/api.php");
$data = json_decode($response, true);
$count = $data['count'] ?? 'N/A';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3-Tier Page Counter</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 500px;
            width: 90%;
        }
        h1 {
            color: #333;
            margin-bottom: 1rem;
            font-size: 2.5rem;
        }
        .counter {
            background: #f8f9fa;
            padding: 2rem;
            border-radius: 15px;
            margin: 2rem 0;
            border-left: 5px solid #667eea;
        }
        .count-number {
            font-size: 3rem;
            font-weight: bold;
            color: #667eea;
            margin: 0.5rem 0;
        }
        .count-label {
            color: #666;
            font-size: 1.1rem;
        }
        .refresh-btn {
            background: linear-gradient(45deg, #667eea, #764ba2);
            color: white;
            padding: 1rem 2rem;
            border: none;
            border-radius: 50px;
            font-size: 1.1rem;
            text-decoration: none;
            display: inline-block;
            transition: transform 0.2s, box-shadow 0.2s;
            cursor: pointer;
        }
        .refresh-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.2);
        }
        .architecture {
            margin-top: 2rem;
            padding: 1rem;
            background: #f1f3f4;
            border-radius: 10px;
            font-size: 0.9rem;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 3-Tier Counter</h1>
        
        <div class="counter">
            <div class="count-label">Total Page Visits</div>
            <div class="count-number"><?= htmlspecialchars($count) ?></div>
        </div>
        
        <a href="/" class="refresh-btn">🔄 Increment Counter</a>
        
        <div class="architecture">
            <strong>Architecture:</strong> Web Tier → App Tier → Database Tier
        </div>
    </div>
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
// Database credentials
$host = "${module.db_instance.private_ip}";
$db = "${var.database_name}";
$user = 'root';
$pass = "${var.database_password}";

// Connect to MySQL
$conn = new mysqli($host, $user, $pass, $db);

// Check connection
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['error' => 'Database connection failed']);
    exit();
}

header('Content-Type: application/json');

// Increment count
// Increment the count
$update = "UPDATE counters SET count = count + 1 WHERE id = 1";
if ($conn->query($update)) {
    // Fetch updated count
    $result = $conn->query("SELECT count FROM counters WHERE id = 1");
    if ($row = $result->fetch_assoc()) {
        echo json_encode(['count' => (int)$row['count']]);
    } else {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch count']);
    }
} else {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to increment count']);
}

$conn->close();
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
      from_port                = 80
      to_port                  = 80
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