# Demo Rollout Instructions

## Steps

**Create a namespace:**

```sh
kubectl create namespace poc-rollouts
```

**Create** the following rollout demo yaml:

```sh
kubectl apply -n poc-rollouts -f demo/bluegreen-demo.yaml
```

For the canary strategy use the `demo/canary-demo.yaml` file.

**Watch** using argo rollouts get:

```sh
kubectl argo rollouts get rollout bluegreen-demo -n poc-rollouts --watch
```

**Update** the rollout image:

```sh
kubectl argo rollouts -n poc-rollouts set image bluegreen-demo bluegreen-demo=argoproj/rollouts-demo:yellow
```

## Debug

`kubectl describe pod -n poc-rollouts rollouts-demo-795c78ccfc-8t8sh`
`kubectl logs -n poc-rollouts rollouts-demo-795c78ccfc-8t8sh`
