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
