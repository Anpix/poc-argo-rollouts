# IAM role do AWS Load Balancer Controller via IRSA, igual ao prod (lá o role
# foi criado pelo eksctl). O chart é instalado pelo helmfile
# (src/eks/helm/helmfile.yaml), que lê o ARN deste role e o id da VPC dos
# outputs.
module "aws_load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "${var.cluster_name}-aws-load-balancer-controller"
  policy_name     = "${var.cluster_name}-aws-load-balancer-controller"
  use_name_prefix = false

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    this = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
