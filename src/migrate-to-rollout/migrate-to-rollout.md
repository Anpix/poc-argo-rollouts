# Convert Deployment to Rollout

## Pre-requisites

**Create a Namespace** if not exists

```sh
kubectl create namespace poc-rollouts
```

**Create a Deployment** if not exists

```sh
kubectl apply -n poc-rollouts -f src/migrate-to-rollout/migrate.deployment.yaml
```

## Steps

**Create a Rollout:**

```sh
kubectl apply -n poc-rollouts -f src/migrate-to-rollout/migrate.rollout.yaml
```

When the `rollout` definition has `workloadRef` then it depends of the `deployment` created before using the `migrate.deployment.yaml` file.
With the `workloadRef` annotation, it's also necessary to create the preview `service`, already located in the `migrate.rollout.yaml` file.

**Watch** the rollout using this command:

```sh
kubectl argo rollouts get rollouts migrate -n poc-rollouts --watch
```

**Update** the rollout image:

```sh
kubectl argo rollouts -n poc-rollouts set image migrate migrate=argoproj/rollouts-demo:blue
```

## Rollback

```sh
kubectl delete -n poc-rollouts -f src/migrate-to-rollout/migrate.deployment.yaml
kubectl delete -n poc-rollouts -f src/migrate-to-rollout/migrate.rollout.yaml
```
