output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "Usado pelo helmfile no --aws-vpc-id do AWS Load Balancer Controller"
  value       = module.vpc.vpc_id
}

output "aws_load_balancer_controller_role_arn" {
  description = "Usado pelo helmfile na service account do AWS Load Balancer Controller (IRSA)"
  value       = module.aws_load_balancer_controller_irsa.arn
}

output "configure_kubectl" {
  description = "Cria o contexto k8-acms-poc esperado pelo src/eks/helm/helmfile.yaml"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --profile ${var.aws_profile} --alias ${var.cluster_name}"
}
