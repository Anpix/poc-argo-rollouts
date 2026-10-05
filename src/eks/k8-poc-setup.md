# Setup: cluster `k8-acms-poc` (EKS + KEDA + Argo Rollouts)

Passo a passo para criar do zero, na conta POC, um cluster EKS.
A ideia é ter um cluster com acesso total para rodar os testes de Argo Rollouts + KEDA.

## Arquivos

- [terraform/terraform-instructions.md](terraform/terraform-instructions.md): cria o cluster e o IAM role do AWS Load Balancer Controller
- [helm/helm-instructions.md](helm/helm-instructions.md): instala metrics-server, KEDA e AWS Load Balancer Controller (ambiente igual ao dev)
- [helm/argo-rollouts-instructions.md](helm/argo-rollouts-instructions.md): instala o Argo Rollouts
- [poc-test/test-instructions.md](poc-test/test-instructions.md): app de teste atrás de um ALB igual ao do 7vote-api em prod, e o load test com k6

## Versões

| Componente     | `k8-dev`                        | `k8-poc`                                |
| -------------- | ------------------------------- | --------------------------------------- |
| Região         | `us-east-2`                     | `us-east-2`                             |
| K8s            | `1.36` (`v1.36.3-eks`)          | `1.36`                                  |
| Criado com     | eksctl `0.205.0`                | Terraform                               |
| OIDC           | habilitado                      | habilitado                              |
| Autenticação   | `API_AND_CONFIG_MAP`            | `API_AND_CONFIG_MAP`                    |
| Endpoint       | público                         | público + privado                       |
| Auto Mode      | desligado                       | desligado                               |
| Nodes          | Karpenter (config desconhecida) | managed nodegroup, 2× `t3.large` AL2023 |
| metrics-server | instalado (versão desconhecida) | `0.9.0` (chart `3.14.0`)                |
| KEDA           | `2.19.0`                        | `2.19.0` (chart `2.19.0`)               |
| Argo Rollouts  | não instalado                   | `v1.9.1` (chart `2.41.1`)               |
| ALB Controller | `v2.13.4` (chart `1.13.4`)¹     | `v2.13.4` (chart `1.13.4`), IRSA        |
| Datadog        | instalados                      | não instalados (opcionais, passo 5)     |
| k6-operator    | instalados                      | não instalados (opcionais, passo 5)     |

¹ Versão lida no `k8-acms-prod` pelo Datadog. No dev, o controller está
instalado (há CRDs `elbv2.k8s.aws`), mas a role `ACMS_Developer` não consegue
ler a versão nem o Ingress. O DNS do `api-7vote-dev` aponta para um ALB do
mesmo IngressGroup (`k8s-igrejas-…`), então a configuração deve ser a mesma.

Manter o K8s 1.36 é proposital. Assim o POC reproduz o mesmo risco de
compatibilidade do dev. Ver o
[plano de compatibilidade](../../docs/argo-rollouts-compatibility-plan.md).

## 0. Pré-requisitos

Ferramentas: `aws` CLI v2, `kubectl` 1.36 e o plugin `kubectl-argo-rollouts`.
Terraform, helm e helmfile estão nos pré-requisitos de cada passo.

```sh
brew install argoproj/tap/kubectl-argo-rollouts   # se ainda não tiver
```

Login na conta POC. O profile `k8-acms-poc` usa a role `AdministratorAccess`
na conta `151567228867`, separada das contas de dev e prod.

```sh
aws sso login --profile k8-acms-poc
aws sts get-caller-identity --profile k8-acms-poc

# Confirmar que o 1.36 está disponível na conta
aws eks describe-cluster-versions --profile k8-acms-poc --region us-east-2 \
  --query 'clusterVersions[].[clusterVersion,versionStatus]' --output table
```

## 1. Criar o cluster

Siga o [terraform-instructions.md](terraform/terraform-instructions.md) até o
passo 3. No fim, o contexto `k8-acms-poc` existe no kubeconfig e passa a ser
o contexto atual. O mesmo `apply` cria o IAM role (IRSA) usado pelo AWS Load
Balancer Controller no passo 2.

> **Atenção:** os scripts de teste do repo usam o contexto atual. Antes de
> rodar qualquer teste, confira com `kubectl config current-context`.

## 2. Instalar metrics-server, KEDA e AWS Load Balancer Controller

Siga o [helm-instructions.md](helm/helm-instructions.md). No fim, o
cluster está igual ao dev, sem Argo Rollouts. Rode no mesmo checkout do passo
1, porque o helmfile lê o `terraform output`.

## 3. Instalar o Argo Rollouts

Siga o
[argo-rollouts-instructions.md](helm/argo-rollouts-instructions.md).

## 4. Karpenter (opcional)

O dev usa Karpenter, mas a versão e os `NodePool`/`EC2NodeClass` não puderam ser
lidos. Ele só faz diferença se os testes fizerem o KEDA escalar além da
capacidade dos nodes. Nesse caso, o tempo para subir um node novo entra no
tempo do rollout.

O Terraform do POC não inclui o Karpenter. Para incluir, é preciso adicionar o
submódulo `terraform-aws-modules/eks/aws//modules/karpenter`, instalar o chart
e criar um `NodePool` e um `EC2NodeClass`, de preferência copiados do dev
quando alguém conseguir exportá-los (ver "O que não foi possível levantar" em
[k8-acms-dev-research.md](k8-acms-dev-research.md)).

## 5. Outros componentes do dev (opcionais)

Nenhum deles é necessário para os testes atuais.

- **Datadog:** útil se o `AnalysisTemplate` do canary for usar o provider
  `datadog` do Argo Rollouts. Precisa de API key e app key.
- **k6-operator:** o dev usa `TestRun` do k6-operator; o POC usa `Job` simples.
  Só instale se quiser rodar os testes do mesmo jeito que no dev.

## 6. Rodar os testes

```sh
kubectl config use-context k8-acms-poc
kubectl config current-context   # confirmar antes de cada bateria
```

Depois siga o mesmo fluxo de sempre:

1. [Rollout isolado](../../docs/instructions.md) com `src/basic/`
2. [Conversão de Deployment para Rollout](../migrate-to-rollout/migrate-to-rollout.md)
3. [Load test](../load-test/load-test-instructions.md)
4. Deployment tests: no POC, use o [poc-test](poc-test/test-instructions.md).
   O [deployment-tests](../deployment-tests/deployment-test-instructions.md)
   grava os logs num `hostPath` da máquina local e só funciona no Rancher
   Desktop. O `poc-test` mantém os logs no próprio Job, para ler com
   `kubectl logs` depois que o teste termina.
5. Integração KEDA → Rollout: `ScaledObject` com
   `scaleTargetRef.apiVersion: argoproj.io/v1alpha1` e `kind: Rollout`
   (passos 3 a 6 do [plano de compatibilidade](../../docs/argo-rollouts-compatibility-plan.md#passo-a-passo))

## 7. Custo e limpeza

Ligado o tempo todo, o cluster custa cerca de **US$ 230/mês** em `us-east-2`:

| Item              | Custo aproximado                                     |
| ----------------- | ---------------------------------------------------- |
| Control plane EKS | US$ 73/mês                                           |
| 2× `t3.large`     | US$ 120/mês                                          |
| NAT Gateway       | US$ 33/mês + tráfego                                 |
| ALB do `poc-demo` | US$ 16/mês + LCU, só enquanto o app de teste existir |

Destrua o cluster quando terminar os testes, seguindo o passo "Destruir" do
[terraform-instructions.md](terraform/terraform-instructions.md). A ordem
importa: primeiro os apps de teste (o Ingress, para o controller apagar o ALB),
depois os releases do Helm e só então o `terraform destroy`.

## Pontos de atenção

- **Argo Rollouts 1.10:** já existe a `v1.10.0` estável (chart `2.43.5`). O
  POC fixa a `v1.9.1` (chart `2.41.1`). As duas versões são testadas no CI só
  até K8s 1.35. Para trocar, altere `version` no
  [helmfile do Argo Rollouts](helm/argo-rollouts/helmfile.yaml).
- **KEDA values:** o [keda/values-dev.yaml](helm/keda/values-dev.yaml) foi
  corrigido contra os values reais do chart 2.19.0. `podDisruptionBudget` agora
  é configurado por componente, e os resources do `webhooks` voltaram aos
  defaults do chart (antes estavam com limit de `50m` de CPU, valor que não é
  default). O arquivo continua sendo uma aproximação, porque não temos o
  `helm get values` real do dev.
- **metrics-server:** a versão do dev é desconhecida. Usamos o chart mais
  recente (`3.14.0` / app `0.9.0`).
- **ALB × prod:** o Ingress do `poc-demo` copia as annotations do Ingress
  `api-7vote` de prod. Ficaram de fora só o HTTPS (o POC não tem domínio nem
  certificado ACM, então é só HTTP:80), o host da regra e o
  `target-node-labels` (o POC não tem Karpenter). Detalhes no
  [poc-demo.yaml](poc-test/poc-demo.yaml).
- **App × prod:** como o 7vote em prod, o `poc-demo` **não tem**
  `readinessProbe`, `livenessProbe` nem `preStop`, e usa o
  `terminationGracePeriodSeconds` default (30s). Ele responde ao health check
  do ALB (`/_Healthcheck/balancer`) igual ao 7vote: `200`, corpo vazio e
  `Cache-Control: no-store, no-cache`. O `/ready`, que só libera 10s depois
  de o pod subir, é usado apenas pelo smoke test do Argo, que tenta de novo
  por até 30s.
- **ALB Controller 3.x:** já existe a `v3.5.0` (chart `3.5.0`). O POC fixa a
  `v2.13.4` de prod. A IAM policy criada pelo Terraform é a mais recente do
  módulo, que também cobre a 2.13.
