
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
