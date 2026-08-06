# Convert Deployment to Rollout

## Pre-requisites

**Create a Namespace** if not exists

```sh
kubectl create namespace poc-rollouts
```

**Create a Deployment** if not exists

```sh
kubectl apply -n poc-rollouts -f demo/deployment-demo.yaml
```

## Steps

**Create a Rollout:**

```sh
kubectl apply -n poc-rollouts -f demo/deployment-bluegreen-rollout.yaml
```

**Watch** using argo rollouts get:

```sh
kubectl argo rollouts get rollout deployment-bluegreen-rollout -n poc-rollouts --watch
```

**Update** the rollout image:

```sh
kubectl argo rollouts -n poc-rollouts set image deployment-demo-rollout deployment-demo=argoproj/rollouts-demo:yellow
```
