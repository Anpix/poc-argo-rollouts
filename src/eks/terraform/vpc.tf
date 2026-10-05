locals {
  # /19 privadas para os pods (VPC CNI usa IPs da subnet), /20 públicas para NAT/LB
  private_subnets = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr, 3, i)]
  public_subnets  = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.cluster_name
  cidr = var.vpc_cidr
  azs  = var.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true # 1 NAT só, para economizar
  enable_dns_hostnames = true

  # Tags usadas pelo AWS Load Balancer Controller (se for instalado depois)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
