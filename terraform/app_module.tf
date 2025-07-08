
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

