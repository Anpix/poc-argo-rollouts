variable "aws_profile" {
  description = "Profile AWS usado para criar o cluster (conta POC)"
  type        = string
}

variable "region" {
  description = "Região AWS (igual ao k8-acms-dev)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS. O src/eks/helm/helmfile.yaml espera um contexto que aponte para este nome"
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do K8s (igual ao k8-acms-dev)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Não pode sobrepor o service CIDR do EKS (10.100.0.0/16)"
  type        = string
}

variable "azs" {
  description = "Availability zones. O control plane do dev usa 2 subnets"
  type        = list(string)
}

variable "node_instance_type" {
  description = "Tipo de instância do nodegroup (o do dev é desconhecido)"
  type        = string
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}
