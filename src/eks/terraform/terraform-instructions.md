# EKS do POC via Terraform

Cria o cluster `k8-acms-poc` na conta POC, espelhando o `k8-acms-dev` (ver
[k8-acms-dev-research.md](../k8-acms-dev-research.md)), com `terraform plan`
para revisar recurso por recurso antes de criar.

O Terraform cuida só da infraestrutura, incluindo o IAM role (IRSA) do AWS
Load Balancer Controller. Os add-ons (metrics-server, KEDA, AWS Load Balancer
Controller e Argo Rollouts) são instalados depois, via Helm (ver
[helm-instructions.md](../helm/helm-instructions.md)). Instalar os charts pelo
provider `helm` no mesmo `apply` que cria o cluster é uma fonte conhecida de
problemas, porque o provider precisa do endpoint de um cluster que ainda não
existe.

## Arquivos

- [versions.tf](versions.tf): versões do Terraform e do provider AWS, profile e região
- [variables.tf](variables.tf): declaração das variáveis
- [terraform.tfvars](terraform.tfvars): **valores** de profile, região, versão do K8s e nodes
- [vpc.tf](vpc.tf): VPC, 2 AZs, subnets públicas/privadas, 1 NAT Gateway
- [eks.tf](eks.tf): cluster EKS, add-ons e managed nodegroup
- [lb-controller.tf](lb-controller.tf): IAM role e policy do AWS Load Balancer Controller (IRSA)
- [outputs.tf](outputs.tf): nome, versão, endpoint, comando de `update-kubeconfig`,
  id da VPC e ARN do role do AWS Load Balancer Controller. Os dois últimos são
  lidos pelo helmfile, então o `terraform.tfstate` precisa estar no repo quando
  os add-ons forem instalados.

## O que é criado

| Item                        | Valor                                                    | Origem                                                  |
| --------------------------- | -------------------------------------------------------- | ------------------------------------------------------- |
| Região                      | `us-east-2`                                              | igual ao dev                                            |
| K8s                         | `1.36`                                                   | igual ao dev                                            |
| Autenticação                | `API_AND_CONFIG_MAP`                                     | igual ao dev                                            |
| OIDC (IRSA)                 | habilitado                                               | igual ao dev                                            |
| Endpoint                    | público + privado                                        | dev: público (privado não verificado)                   |
| Subnets do control plane    | 2 (privadas)                                             | igual ao dev                                            |
| Add-ons EKS                 | `vpc-cni`, `kube-proxy`, `coredns` (versão mais recente) | padrão                                                  |
| Nodes                       | managed nodegroup `ng-default`, 2× `t3.large`, AL2023    | dev usa Karpenter (config desconhecida)                 |
| VPC                         | `10.0.0.0/16`; privadas `/19`, públicas `/20`            | CIDR do dev desconhecido                                |
| Upgrade policy              | `STANDARD`                                               | dev usa `EXTENDED` (ver comentário em [eks.tf](eks.tf)) |
| Admin do cluster            | quem roda o `apply` (role SSO do `k8-acms-poc`)          | —                                                       |
| KMS e logs do control plane | desligados                                               | igual ao padrão do eksctl, usado no dev                 |
| IAM do ALB Controller       | role `k8-acms-poc-aws-load-balancer-controller` (IRSA)   | igual ao prod (lá criado pelo eksctl)                   |

Módulos usados: `terraform-aws-modules/eks/aws` `~> 21.26`,
`terraform-aws-modules/vpc/aws` `~> 6.7` e
`terraform-aws-modules/iam/aws` `~> 6.8` (submódulo
`iam-role-for-service-accounts`), com provider AWS `~> 6.67`.

## Passo a passo

### 0. Pré-requisitos

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version   # >= 1.5.7

# usado no passo 3
brew install kubectl

aws sso login --profile k8-acms-poc
aws sts get-caller-identity --profile k8-acms-poc
```

### 1. Inicializar e revisar

Os passos 1 a 3 rodam dentro de `src/eks/terraform/`. Partindo da raiz do repo:

```sh
cd src/eks/terraform
terraform init       # baixa provider e módulos; não cria nada na AWS
terraform validate
terraform plan -out=poc.tfplan
```

Revise o plano. Devem aparecer cerca de 50 recursos a criar: VPC, subnets,
NAT, IAM roles, cluster, add-ons, nodegroup, access entry e o role/policy do
AWS Load Balancer Controller.

### 2. Criar

Leva de 15 a 20 minutos.

```sh
terraform apply poc.tfplan
```

### 3. Configurar o kubectl

```sh
$(terraform output -raw configure_kubectl)

kubectl --context k8-acms-poc version
kubectl --context k8-acms-poc get nodes -o wide
```

Isso cria o contexto `k8-acms-poc`, que é o que o helmfile espera, e
também o torna o contexto atual.

### Próximo passo: add-ons via Helm

Com o cluster criado, instale os add-ons seguindo o
[helm-instructions.md](../helm/helm-instructions.md).

### 4. Destruir

Os releases do Helm e os load balancers criados pelo cluster não estão no
state do Terraform. Os ALB/ELB e seus security groups bloqueiam a remoção da
VPC. Antes de destruir, nesta ordem:

1. Remova os apps de teste (`kubectl delete namespace load-test`, ver o
   [test-instructions.md](../poc-test/test-instructions.md#cleanup)). Apagar o
   Ingress faz o AWS Load Balancer Controller apagar o ALB, então o controller
   precisa estar rodando nessa hora.
2. Remova o Argo Rollouts e os add-ons base, seguindo a seção "Remover" do
   [argo-rollouts-instructions.md](../helm/argo-rollouts-instructions.md#5-remover)
   e do [helm-instructions.md](../helm/helm-instructions.md#5-remover).

```sh
# devem estar vazios
kubectl --context k8-acms-poc get ingress -A
kubectl --context k8-acms-poc get svc -A | grep LoadBalancer
aws elbv2 describe-load-balancers --profile k8-acms-poc --region us-east-2 \
  --query 'LoadBalancers[].LoadBalancerName'
aws elb describe-load-balancers --profile k8-acms-poc --region us-east-2 \
  --query 'LoadBalancerDescriptions[].LoadBalancerName'

cd src/eks/terraform
terraform destroy
kubectl config delete-context k8-acms-poc
```

## Observações

- **State local:** o `terraform.tfstate` fica em `src/eks/terraform/` e está no
  [.gitignore](.gitignore). Não apague esse arquivo enquanto o cluster
  existir, senão o `destroy` não funciona. Se mais de uma pessoa for aplicar,
  migre para um backend S3.
- **`.terraform.lock.hcl`:** é gerado no `terraform init` e deve ser commitado,
  para fixar as versões dos providers.
- **Mudanças no `desired_size`:** o módulo ignora alterações no `desired_size`
  depois da criação, para não brigar com autoscalers. Para mudar a
  quantidade de nodes, ajuste `min_size`.
- **Disco dos nodes:** usa o default do EKS (20 GiB). Mudar exige um bloco
  `block_device_mappings` no nodegroup.
