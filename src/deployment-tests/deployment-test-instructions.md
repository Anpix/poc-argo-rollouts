# Deployment Test Instructions

## Pre-requisites

**Create the Namespace** if not exists

```sh
kubectl create namespace deployment-tests
```

**Apply** to create the shared k6 test script. This ConfigMap is reused by every test job.

```sh
kubectl apply -n deployment-tests -f src/deployment-tests/deployment-test-k6.yaml
```

**Apply** to create the logs volume (PV + PVC).
Every test job writes its `.log` file into this folder. Run this from the repo root, since `$PWD` gets substituted into the `hostPath`:

```sh
sed "s#\$PWD#$PWD#g" src/deployment-tests/logs-volume.yaml | \
  kubectl apply -n deployment-tests -f -
```

**Allow** the script to be run:

```sh
chmod +x ./src/deployment-tests/run-test.sh
```

## Steps

**Customize and Run** the following command to start a test job:

- `JOB_NAME`: unique job name (e.g. `test-app`)
- `TEST_URL`: URL to be tested. Use a cluster DNS name (`<svc>.<namespace>.svc.cluster.local`) or a public URL. Must be reachable from inside the pod
- `TIMEOUT`: (optional) timeout for each request. Defaults to `5s`.
- `RATE`: (optional) requests per second to sustain. Defaults to `10`.
- `DURATION`: (optional) how long to keep sending requests at that rate. Defaults to `30s`.

```sh
./src/deployment-tests/run-test.sh JOB_NAME TEST_URL TIMEOUT RATE DURATION
```

Example (in-cluster target): `./src/deployment-tests/run-test.sh test-app http://deployment-demo.load-test.svc.cluster.local:7001`
Example (external target, 5s of request timeout, 5 req/s for 30s): `./src/deployment-tests/run-test.sh test-external https://localhost:7000 5s 5 30s`

**Rollout** a new version for your app, if that's what you're testing.

**Open** the log file created in this folder (`src/deployment-tests/*.log`) to see the results.

## Rollback

**CAUTION! DESTRUCTRIVE ACTIONS!**

To delete the whole structure use:

```sh
kubectl delete -n deployment-tests -f src/deployment-tests/logs-volume.yaml --ignore-not-found
kubectl delete -n deployment-tests -f src/deployment-tests/deployment-test-k6.yaml --ignore-not-found
kubectl delete namespace deployment-tests --ignore-not-found
```
