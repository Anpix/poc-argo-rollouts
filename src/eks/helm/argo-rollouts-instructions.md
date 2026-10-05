# Argo Rollouts no POC via helmfile

Instala o Argo Rollouts no cluster `k8-acms-poc` **depois** do ambiente base
(metrics-server + KEDA, igual ao dev). Fica num helmfile separado para que o
ambiente base possa ser criado e validado sem o Argo, como está no dev hoje.

| Add-on        | Versão                    | Namespace       |
| ------------- | ------------------------- | --------------- |
| Argo Rollouts | `v1.9.1` (chart `2.41.1`) | `argo-rollouts` |

## Arquivos

- [argo-rollouts/helmfile.yaml](argo-rollouts/helmfile.yaml): repositório,
  release, versão do chart e a trava de contexto
- [argo-rollouts/values-dev.yaml](argo-rollouts/values-dev.yaml): values do chart

## 1. Pré-requisitos

- helmfile e helm-diff instalados (passo 1 do
  [helm-instructions.md](helm-instructions.md#1-pré-requisitos-uma-vez)).
- Ambiente base instalado e validado (passos 2 e 3 do
  [helm-instructions.md](helm-instructions.md#2-instalar)).

## 2. Instalar

Da raiz do repo:

```sh
helmfile -f src/eks/helm/argo-rollouts/helmfile.yaml diff    # mostra o que vai mudar no cluster
helmfile -f src/eks/helm/argo-rollouts/helmfile.yaml apply   # aplica só o que mudou
```

O release usa a mesma trava de contexto do helmfile base: só roda se o
contexto `k8-acms-poc` apontar para o cluster `k8-acms-poc`. O namespace
`argo-rollouts` é criado se não existir, e o `apply` espera o controller ficar
pronto (timeout de 10 min).

Se o `apply` for interrompido, o release fica `failed`. Remova e aplique de
novo:

```sh
helm --kube-context k8-acms-poc uninstall argo-rollouts -n argo-rollouts
helmfile -f src/eks/helm/argo-rollouts/helmfile.yaml apply
```

## 3. Validar

O controller deve subir sem `CrashLoopBackOff` nem erros de RBAC/webhook
(passo 2 do
[plano de compatibilidade](../../../docs/argo-rollouts-compatibility-plan.md)):

```sh
helm --kube-context k8-acms-poc list -n argo-rollouts
kubectl --context k8-acms-poc get pods -n argo-rollouts
kubectl --context k8-acms-poc logs -n argo-rollouts deploy/argo-rollouts --tail=50

# CRDs do Argo Rollouts
kubectl --context k8-acms-poc get crd | grep argoproj.io
```

Depois siga os passos 3 a 6 do
[plano de compatibilidade](../../../docs/argo-rollouts-compatibility-plan.md#passo-a-passo).

## 4. Mudar versão ou values

Altere `version` no [argo-rollouts/helmfile.yaml](argo-rollouts/helmfile.yaml)
ou o [argo-rollouts/values-dev.yaml](argo-rollouts/values-dev.yaml), rode `diff` e depois `apply`. Para ver as
versões disponíveis:

```sh
helmfile -f src/eks/helm/argo-rollouts/helmfile.yaml repos
helm search repo argo/argo-rollouts --versions | head
```

## 5. Remover

Remova os `Rollout` e demais recursos `argoproj.io` das aplicações antes, senão
eles ficam órfãos sem controller. Depois:

```sh
helmfile -f src/eks/helm/argo-rollouts/helmfile.yaml destroy
```

O ambiente base continua instalado. Para voltar a um cluster igual ao dev,
confira que os CRDs do Argo saíram:

```sh
kubectl --context k8-acms-poc get crd | grep argoproj.io   # deve estar vazio
```

O chart tem `keepCRDs: true` por padrão, então os CRDs continuam lá depois do
`destroy`. Nesse caso, remova à mão:

```sh
kubectl --context k8-acms-poc get crd -o name | grep argoproj.io \
  | xargs kubectl --context k8-acms-poc delete
```
