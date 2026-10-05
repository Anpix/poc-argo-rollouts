module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # --- igual ao k8-acms-dev ---
  authentication_mode     = "API_AND_CONFIG_MAP"
  enable_irsa             = true # OIDC
  endpoint_public_access  = true
  endpoint_private_access = true

  # O dev usa EXTENDED. Aqui fica STANDARD de propósito: se o cluster for
  # esquecido ligado, o EKS faz upgrade automático no fim do suporte padrão
  # em vez de cobrar suporte estendido. Não faz diferença enquanto o 1.36
  # estiver em suporte padrão.
  upgrade_policy = {
    support_type = "STANDARD"
  }

  # Dá admin no cluster para quem roda o terraform apply (role SSO do
  # profile k8-acms-poc).
  enable_cluster_creator_admin_permissions = true

  # --- defaults do módulo desligados para ficar igual a um cluster eksctl ---
  # Sem chave KMS própria para secrets (o EKS já criptografa com chave da AWS)
  # e sem logs do control plane no CloudWatch (custo).
  encryption_config           = null
  create_kms_key              = false
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # O dev usa Karpenter, mas a configuração dele não pôde ser lida.
  # Começamos com um managed nodegroup fixo.
  eks_managed_node_groups = {
    default = {
      name           = "ng-default"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }
}
