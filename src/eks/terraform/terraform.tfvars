# Valores alinhados ao k8-acms-dev (ver src/eks/k8-acms-dev-research.md).

aws_profile = "k8-acms-poc"
region      = "us-east-2"

cluster_name       = "k8-acms-poc"
kubernetes_version = "1.36"

vpc_cidr = "10.0.0.0/16"
azs      = ["us-east-2a", "us-east-2b"]

node_instance_type = "t3.large"
node_min_size      = 2
node_max_size      = 4
node_desired_size  = 2
