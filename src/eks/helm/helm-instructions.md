# Add-ons base do POC via helmfile

Sobe no cluster `k8-acms-poc`, criado pelo
[Terraform](../terraform/terraform-instructions.md), os mesmos add-ons que
existem hoje no `k8-acms-dev`/`k8-acms-prod`. O resultado é um ambiente igual
ao dev, **sem** o Argo Rollouts.

| Add-on                       | Versão                     | Namespace     |
| ---------------------------- | -------------------------- | ------------- |
| metrics-server               | `0.9.0` (chart `3.14.0`)   | `kube-system` |
| KEDA                         | `2.19.0` (chart `2.19.0`)  | `keda`        |
| AWS Load Balancer Controller | `v2.13.4` (chart `1.13.4`) | `kube-system` |

O AWS Load Balancer Controller cria os ALBs dos Ingress com
`ingressClassName: alb`. A versão e os args são os do release em prod (lidos
pelo Datadog, ver [values.yaml.gotmpl](aws-load-balancer-controller/values.yaml.gotmpl)).

O Argo Rollouts é instalado depois, por um helmfile separado. Ver
[argo-rollouts-instructions.md](argo-rollouts-instructions.md).

## Arquivos

- [helmfile.yaml](helmfile.yaml): repositórios, releases, versões dos charts e
  a trava de contexto
- [keda/values-dev.yaml](keda/values-dev.yaml): values do KEDA. O
  metrics-server usa os defaults do chart.
- [aws-load-balancer-controller/values.yaml.gotmpl](aws-load-balancer-controller/values.yaml.gotmpl):
  values do AWS Load Balancer Controller. O id da VPC e o ARN do role IRSA
  vêm do `terraform output`.

## 1. Pré-requisitos (uma vez)

```sh
brew install helm helmfile
helmfile init
helm diff version
helmfile --version
```

O cluster precisa existir e o contexto `k8-acms-poc` precisa estar no kubeconfig.
Ver os passos 1 a 3 do [terraform-instructions.md](../terraform/terraform-instructions.md).

O release do AWS Load Balancer Controller roda `terraform output` em
`src/eks/terraform/`. Por isso, rode o helmfile no mesmo checkout em que
o `terraform apply` foi feito, com o `terraform` instalado. Ele só lê o
`terraform.tfstate` local, sem precisar de login na AWS.

## 2. Instalar

Da raiz do repo:

```sh
helmfile -f src/eks/helm/helmfile.yaml diff    # mostra o que vai mudar no cluster
helmfile -f src/eks/helm/helmfile.yaml apply   # aplica só o que mudou
```

- **Contexto:** todos os releases usam `kubeContext: k8-acms-poc`, não importa
  qual seja o contexto atual do kubectl.
- **Trava de segurança:** antes de cada release, um hook confere se o
  contexto `k8-acms-poc` existe e aponta para um cluster chamado
  `k8-acms-poc`. Se não apontar, o helmfile aborta sem tocar no cluster, como o
  script fazia.
- **Namespaces:** `keda` é criado se não existir.
- **CRDs do ALB Controller:** o release usa `disableValidationOnInstall`.
  Sem isso, a primeira instalação falha no `helm diff` com
  `no matches for kind "IngressClassParams"`, porque o CRD ainda não existe.
- **Espera:** cada release espera os pods ficarem prontos (`wait`, timeout de
  10 min), como o `--wait` do script.

Para reinstalar tudo mesmo sem diferenças, use `sync` no lugar de `apply`.
Para mexer em um release só, filtre pelo nome:

```sh
helmfile -f src/eks/helm/helmfile.yaml -l name=keda apply
```

### Se um install for interrompido

Cancelar o `apply` (Ctrl+C) no meio de um release deixa esse release com status
`failed` e alguns recursos criados pela metade. Isso inclui o APIService
`v1beta1.metrics.k8s.io` sem endpoints, que faz o `kubectl` reclamar de
discovery. Para limpar, remova o release e aplique de novo:

```sh
helm --kube-context k8-acms-poc list -A --failed
helm --kube-context k8-acms-poc uninstall <release> -n <namespace>
helmfile -f src/eks/helm/helmfile.yaml apply
```

## 3. Validar

```sh
helm --kube-context k8-acms-poc list -A
kubectl --context k8-acms-poc get pods -n kube-system -l app.kubernetes.io/name=metrics-server
kubectl --context k8-acms-poc get pods -n keda

# versão do KEDA (deve ser 2.19.0)
kubectl --context k8-acms-poc get crd scaledobjects.keda.sh \
  -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}'

# metrics-server respondendo
kubectl --context k8-acms-poc top nodes

# AWS Load Balancer Controller: 2/2 pods, IngressClass alb e sem erro de IAM
kubectl --context k8-acms-poc get deploy -n kube-system aws-load-balancer-controller
kubectl --context k8-acms-poc get ingressclass alb
kubectl --context k8-acms-poc logs -n kube-system deploy/aws-load-balancer-controller --tail=100 \
  | grep -iE '"level":"error"|AccessDenied'   # não deve listar nada

# sem Argo Rollouts, como no dev (não deve listar nada)
kubectl --context k8-acms-poc get crd | grep argoproj.io
```

Com o ambiente base validado, siga para o
[argo-rollouts-instructions.md](argo-rollouts-instructions.md).

## 4. Mudar versões ou values

Altere `version` no [helmfile.yaml](helmfile.yaml) ou o `values-dev.yaml` do
chart, rode `diff` e depois `apply`. Para ver as versões disponíveis:

```sh
helmfile -f src/eks/helm/helmfile.yaml repos
helm search repo kedacore/keda --versions | head
```

## 5. Remover

Remova antes o Argo Rollouts, se estiver instalado (ver
[argo-rollouts-instructions.md](argo-rollouts-instructions.md#5-remover)).
Os releases do Helm não estão no state do Terraform, então remova-os antes do
`terraform destroy`.

Antes, apague todos os Ingress, com o controller ainda rodando. É ele quem
apaga os ALBs. Sem o controller, o finalizer deixa o Ingress travado e o ALB
fica órfão na conta, bloqueando o `terraform destroy`.

```sh
kubectl --context k8-acms-poc get ingress -A   # deve estar vazio
helmfile -f src/eks/helm/helmfile.yaml destroy
```

O chart do AWS Load Balancer Controller deixa os CRDs `elbv2.k8s.aws` no
cluster. Eles somem junto com o cluster no `terraform destroy`.

Depois, destrua o cluster. O `terraform destroy` roda em `src/eks/terraform/`,
onde está o state, e não na raiz do repo. Ver o passo 4 do
[terraform-instructions.md](../terraform/terraform-instructions.md#4-destruir).
