# K8s POC - Load Test Instructions

Runs a k6 load test as a Kubernetes Job while a new version of the `poc-demo`
Rollout is promoted. When the test finishes, the run script saves the Job logs
to a file in this folder and deletes the Job.

## Files

- [poc-demo.yaml](poc-demo.yaml): `poc-demo` app (blue-green Rollout), its `poc-demo` (NodePort) / `poc-demo-preview` (ClusterIP) Services and the `poc-demo` Ingress, which creates an ALB with the same settings as the 7vote-api one in prod
- [smoke-test-template.yaml](smoke-test-template.yaml): `smoke-tests` AnalysisTemplate used by the Rollout before and after promotion
- [poc-test-k6.yaml](poc-test-k6.yaml): ConfigMap with the k6 script (one JSON line per request) and the Job template, filled in by the run script
- [poc-test-run.sh](poc-test-run.sh): creates the Job with the given parameters, waits for it to finish, saves its logs and deletes it

## Pre-requisites

Every command uses the current context. Check it before starting:

```sh
kubectl config current-context   # must be k8-acms-poc
```

The AWS Load Balancer Controller must be installed (see
[helm-instructions.md](../helm/helm-instructions.md)), otherwise the Ingress
never gets an ALB.

Start from a clean cluster: the `load-test` namespace should not exist (see [Cleanup](#cleanup)).

**Create the Namespace** `load-test`:

```sh
kubectl create namespace load-test
```

**Create the Template** `smoke-tests`:

```sh
kubectl apply -n load-test -f src/eks/poc-test/smoke-test-template.yaml
```

**Apply** to create the `poc-demo` app and wait for it to be `Healthy`:

```sh
kubectl apply -n load-test -f src/eks/poc-test/poc-demo.yaml
kubectl argo rollouts status poc-demo -n load-test
```

**Wait for the ALB** and save its address. The hostname shows up in about a
minute, but the ALB takes 2 to 3 more minutes to be active and its DNS to
resolve:

```sh
ALB=$(kubectl get ingress poc-demo -n load-test -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $ALB   # empty while the ALB is being created
until curl -sf -o /dev/null "http://$ALB/"; do sleep 10; done; curl -s "http://$ALB/"
```

The ALB copies the prod settings: `target-type: instance` (ALB → NodePort →
pod), health check `/_Healthcheck/balancer` every 5s, idle timeout 600s. The
only listener is HTTP:80, because the POC has no domain nor certificate.

## Steps

### 1. Run the test

```sh
./src/eks/poc-test/poc-test-run.sh <job-name> <test-url> [timeout] [rate] [duration]
```

| Parameter  | Default | Description                                                   |
| ---------- | ------- | ------------------------------------------------------------- |
| `job-name` | —       | Job name; also used in the log file name                      |
| `test-url` | —       | URL called on every request                                   |
| `timeout`  | `5s`    | Timeout of each request                                       |
| `rate`     | `10`    | Requests per second                                           |
| `duration` | `30s`   | Test duration, in a single unit (`300s` or `5m`, not `4m30s`) |

Examples:

```sh
# poc-demo through the ALB, like a client of 7vote-api in prod
./src/eks/poc-test/poc-test-run.sh poc-test-demo "http://$ALB/" 5s 20 30s

# poc-demo through the internal DNS, skipping the ALB
./src/eks/poc-test/poc-test-run.sh poc-test-internal http://poc-demo.load-test.svc.cluster.local/ 5s 20 300s

# any other address
./src/eks/poc-test/poc-test-run.sh poc-test-7vote https://my-address/api/version 20s 100 30s
```

The script:

- applies the k6 script ConfigMap and creates the Job (it stops if a Job with the same name already exists);
- waits for the Job to finish and prints the result. k6 exits with code `99`
  when any request is not 2xx, which marks the Job as `Failed`. The logs are
  complete in both cases;
- saves the logs to `src/eks/poc-test/<job-name>-<YYYYMMDD-HHMM>.log` (local
  time; `*.log` is ignored by git);
- deletes the Job, only after the log file was saved and is not empty.

The Job is **kept** when the logs can't be saved, when it is still running
after the wait (`duration` + 120s), or when the script is stopped with Ctrl+C
(the test keeps running). In these cases, save the logs and delete the Job by
hand (see [Get the logs](#3-get-the-logs)). Finished Jobs are deleted
automatically 24h after they finish anyway.

### 2. Rollout a new version

While the test is running, in another terminal, rollout a new version with a new `APP_VERSION` value:

```sh
kubectl patch rollout poc-demo -n load-test --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"green"}]'
kubectl argo rollouts get rollout poc-demo -n load-test --watch
```

### 3. Get the logs

The run script already saves them to `src/eks/poc-test/<job-name>-<YYYYMMDD-HHMM>.log`.

The log has one JSON line per request (`req_start`, `req_end`, `status`,
`body`, plus `error`/`error_code` on failures), followed by the k6 summary.
k6 also prints a `Request Failed` line for each transport error (timeout,
connection refused, TLS). To keep only the request lines:

```sh
grep '^{' src/eks/poc-test/poc-test-demo-20261005-1930.log > poc-test-demo.filtered.log
```

If the Job was kept (see above), save the logs and delete it by hand:

```sh
kubectl logs -n load-test job/poc-test-demo > src/eks/poc-test/poc-test-demo.log
kubectl delete job poc-test-demo -n load-test
```

While the Job exists, its logs stay available:

- **TTL:** the Job is deleted automatically **24h** after it finishes
  (`ttlSecondsAfterFinished` in [poc-test-k6.yaml](poc-test-k6.yaml)).
- **Size:** the kubelet rotates container logs at 10 MiB, and `kubectl logs`
  only returns the latest file. Each request line has about 110 bytes, so this
  holds about 90k requests (e.g. 20 req/s for ~75 min). For longer tests, split
  them into several Jobs.
- **Node:** if the node running the pod is removed, the logs are lost.

## Cleanup

If any test Job was kept, save its logs first. Deleting the namespace removes the app, the Jobs and their logs:

```sh
kubectl delete namespace load-test
```

Deleting the namespace also deletes the Ingress, and the AWS Load Balancer
Controller then deletes the ALB. Do it before removing the controller and
before `terraform destroy`, otherwise the ALB is left behind and blocks the
VPC removal. To confirm it's gone:

```sh
aws elbv2 describe-load-balancers --profile k8-acms-poc --region us-east-2 \
  --query 'LoadBalancers[].LoadBalancerName'   # no k8s-poc-* entry
```
