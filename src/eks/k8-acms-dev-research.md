# Levantamento: cluster `k8-acms-dev`

Levantamento feito em 05/10/2026 para replicar o `k8-acms-dev` num cluster
próprio (ver [k8-poc-setup.md](k8-poc-setup.md)), já que não temos
acesso ao `helm` nem aos workloads do dev.

## Como foi levantado (e limitações)

Tudo foi lido com acesso somente leitura, usando o profile `k8-acms-dev`
(role SSO `ACMS_Developer`, conta `186435305431`).

**AWS API:** só `eks:ListClusters` e `eks:DescribeCluster` funcionam. Retornaram
`AccessDenied`:

- `eks:ListNodegroups`, `eks:ListAddons`, `eks:ListFargateProfiles`
- `cloudformation:DescribeStacks`
- `ec2:DescribeInstances`

**Kubernetes (contexto `k8-acms-dev`):** só temos `get/list` em `namespaces` e
`customresourcedefinitions`, além dos endpoints de discovery (`/api`, `/apis`,
`/version`, `/openapi`). `kubectl auth can-i list` retornou `no` para:

- `nodes`, `pods`, `services`, `configmaps`, `secrets`, `deployments`
- `scaledobjects.keda.sh`, `horizontalpodautoscalers`, `ingresses`
- `nodepools.karpenter.sh`, `ec2nodeclasses.karpenter.k8s.aws`, `apiservices`

Por isso as versões abaixo vêm de labels de CRDs (`app.kubernetes.io/version`,
`helm.sh/chart`) e da presença de API groups. Elas indicam o que está instalado,
mas não a configuração.

## Cluster EKS

Fonte: `aws eks describe-cluster --name eks-cluster-002 --region us-east-2`.

| Item                      | Valor                                       |
| ------------------------- | ------------------------------------------- |
| Nome                      | `eks-cluster-002`                           |
| Região                    | `us-east-2`                                 |
| Versão K8s                | `1.36` (server `v1.36.3-eks-cb19647`)       |
| Platform version          | `eks.11`                                    |
| Criado com                | **eksctl `0.205.0`** (stack CloudFormation `eksctl-eks-cluster-002-cluster`) |
| Upgrade policy            | `EXTENDED`                                  |
| Autenticação              | `API_AND_CONFIG_MAP`                        |
| OIDC (IRSA)               | habilitado                                  |
| Endpoint público          | sim                                         |
| Subnets do control plane  | 2                                           |
| Service CIDR              | `10.100.0.0/16` (IPv4)                      |
| EKS Auto Mode             | desligado (`elasticLoadBalancing.enabled: false`, `computeConfig: null`) |
| Tag `karpenter.sh/discovery` | `eks-cluster-002` (cluster usa Karpenter) |

## Componentes instalados

Inferidos de CRDs, namespaces e API groups (`kubectl get crd`, `kubectl get ns`,
`kubectl api-versions`).

| Componente                    | Evidência                                                        | Versão                                       |
| ----------------------------- | ---------------------------------------------------------------- | -------------------------------------------- |
| KEDA                          | ns `keda` (136 dias), CRDs `keda.sh` e `eventing.keda.sh`, API `external.metrics.k8s.io` | **`2.19.0`**, chart `keda-2.19.0` |
| Karpenter                     | CRDs `karpenter.sh/v1` (`nodepools`, `nodeclaims`) e `karpenter.k8s.aws/v1` (`ec2nodeclasses`) | ≥ 1.0 (API v1); versão exata desconhecida. Não há ns `karpenter`, então o controller provavelmente roda no `kube-system` |
| AWS Load Balancer Controller  | CRDs `elbv2.k8s.aws` (`targetgroupbindings`, `ingressclassparams`) e `gateway.k8s.aws` | desconhecida |
| metrics-server                | API `metrics.k8s.io/v1beta1` registrada                          | desconhecida                                 |
| Datadog Operator              | ns `datadog`, CRDs `datadoghq.com`                               | CRDs do chart `datadogCRDs-2.23.0`           |
| k6-operator                   | ns `k6-operator-system`, CRDs `k6.io` (`testruns`, `privateloadzones`) | desconhecida                           |
| Amazon VPC CNI                | CRDs `eniconfigs.crd.k8s.amazonaws.com`, `cninodes`, `securitygrouppolicies` | add-on padrão do EKS                |
| VPC CNI network policy        | CRDs `networking.k8s.aws` (`policyendpoints`, `clusternetworkpolicies`, `applicationnetworkpolicies`) | add-on padrão do EKS |
| Métricas do control plane EKS | API `metrics.eks.amazonaws.com/v1`                               | gerenciado pela AWS                          |
| **Argo Rollouts**             | nenhum CRD `argoproj.io`                                         | **não instalado**                            |

## Namespaces

```text
azure-agents, azuredevops     # agentes do Azure DevOps
datadog                       # Datadog Operator/Agent
dev, staging, sandbox         # aplicações
k6-operator-system            # k6-operator
keda                          # KEDA
default, kube-system, kube-public, kube-node-lease
```

## Observações

- **ALB Ingress:** o AWS Load Balancer Controller está instalado (há CRDs
  `elbv2.k8s.aws`), o que responde em parte o "Usamos ALB Ingress?" do README.
  Sem permissão para listar `ingresses`, não foi possível confirmar se há
  Ingress em uso.
- **k6:** o dev usa o k6-operator (`TestRun`). Os testes deste POC
  (`src/load-test/`, `src/deployment-tests/`) usam um `Job` simples com a
  imagem `grafana/k6`.
- **Datadog:** como o Datadog já está no cluster, o `AnalysisTemplate` do Argo
  Rollouts pode usar o provider `datadog` para análise de canary.
- **Versões fora da janela de teste:** K8s 1.36 continua fora da janela
  testada pelo KEDA 2.19 e pelo Argo Rollouts (ver
  [argo-rollouts-compatibility-plan.md](../../docs/argo-rollouts-compatibility-plan.md)).

## O que não foi possível levantar

Peça para alguém com acesso administrativo ao `k8-acms-dev` rodar os comandos
abaixo e anexar a saída aqui:

```sh
# Values reais do KEDA (para atualizar src/eks/helm/keda/values-dev.yaml)
helm get values keda -n keda --all

# Releases Helm instalados (versões de Karpenter, ALB Controller, metrics-server, k6-operator)
helm list -A

# Nodes: tipo de instância, nodegroup/nodepool, zona
kubectl get nodes -L node.kubernetes.io/instance-type,eks.amazonaws.com/nodegroup,karpenter.sh/nodepool,topology.kubernetes.io/zone

# Configuração do Karpenter
kubectl get nodepools,ec2nodeclasses -o yaml
kubectl get deploy -A -l app.kubernetes.io/name=karpenter -o jsonpath='{..image}'

# Add-ons e nodegroups gerenciados
aws eks list-addons --cluster-name eks-cluster-002 --region us-east-2
aws eks list-nodegroups --cluster-name eks-cluster-002 --region us-east-2

# Uso de Ingress/ALB
kubectl get ingress,ingressclass -A
```
