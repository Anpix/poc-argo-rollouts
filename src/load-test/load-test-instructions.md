# Load Test Instructions

## Pre-requisites

**Create a Namespace** if not exists

```sh
kubectl create namespace load-test
```

**Create the Template** `smoke-test` if not exists

```sh
kubectl apply -n load-test -f src/analysis-templates/smoke-tests-analysistemplate.yaml
```

**Customize** the Deployment parameters, if necessary. The default delay is 10 sec.

If you need to change the delay time, edit the `sleep 10` value in the container `args` in the [deployment-demo.yaml](./deployment-demo.yaml) file.

**Apply** to create the `deployment-demo` app:

```sh
kubectl apply -n load-test -f src/load-test/deployment-demo.yaml
```

## Steps

**Customize** the `load-test` app parameters, if necessary.

If you need to change the values, edit the `args` list in the [load-test-demo.yaml](./load-test-demo.yaml) file.

- `-c=8`: concurrent tasks
- `-qps=20`: requests per second
- `-t=15s`: test duration

> The `fortio/fortio` image has no shell, so the container can't loop on its own. Each `fortio load` run exits after `-t` elapses; the pod's `restartPolicy: Always` restarts the container automatically for the next cycle. Note that the kubelet applies an increasing back-off delay (10s, 20s, 40s, ...) between restarts, so the gap between cycles grows over time instead of staying fixed.

**Apply** to create the `load-test-demo` app:

```sh
kubectl apply -n load-test -f src/load-test/load-test-demo.yaml
```

**Watch** the application logs using:

```sh
kubectl logs -n load-test -f deploy/load-test-demo | tee "src/load-test/load-test-$(date +%Y%m%d-%H)h.log"
```

**Rollout** a new vcersion with the new `APP_VERSION` value:

```sh
kubectl patch rollout deployment-demo -n load-test --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"green"}]'

```

## Rollback

```sh
kubectl delete -n load-test -f src/load-test/deployment-demo.yaml
```
