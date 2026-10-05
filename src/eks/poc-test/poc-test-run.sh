#!/bin/sh
set -eu

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "Usage: $0 <job-name> <test-url> [timeout] [rate] [duration]" >&2
  exit 1
fi

JOB_NAME="$1"
TEST_URL="$2"
TIMEOUT="${3:-5s}"
RATE="${4:-10}"
DURATION="${5:-30s}"
NAMESPACE=load-test
DIR="$(dirname "$0")"

# escape characters that have a special meaning in the sed replacement (e.g. "&" in a query string)
esc() { printf '%s' "$1" | sed 's/[#&\\]/\\&/g'; }

if kubectl get job "$JOB_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "Job $JOB_NAME already exists. Save its logs and delete it, or use another name:" >&2
  echo "  kubectl logs -n $NAMESPACE job/$JOB_NAME > $DIR/$JOB_NAME.log" >&2
  echo "  kubectl delete job $JOB_NAME -n $NAMESPACE" >&2
  exit 1
fi

echo "Context: $(kubectl config current-context)"
echo "Creating job $JOB_NAME to run..."
sed \
  -e "s#\$JOB_NAME#$(esc "$JOB_NAME")#g" \
  -e "s#\$TEST_URL#$(esc "$TEST_URL")#g" \
  -e "s#\$TIMEOUT#$(esc "$TIMEOUT")#g" \
  -e "s#\$RATE#$(esc "$RATE")#g" \
  -e "s#\$DURATION#$(esc "$DURATION")#g" \
  "$DIR/poc-test-k6.yaml" | \
kubectl apply -f -

# only handles a single unit (e.g. "30s" or "2m"), not combined ones like "1m30s"
case "$DURATION" in
  *m) DURATION_SECONDS=$(( $(echo "$DURATION" | sed 's/m$//') * 60 )) ;;
  *s) DURATION_SECONDS=$(echo "$DURATION" | sed 's/s$//') ;;
  *) DURATION_SECONDS=30 ;;
esac
WAIT_TIMEOUT=$((DURATION_SECONDS + 120))

# k6 exits non-zero when a threshold fails (any non-2xx), which marks the job as
# Failed, so wait for either Complete or Failed instead of `kubectl wait --for=condition=complete`
echo "Waiting up to ${WAIT_TIMEOUT}s for job $JOB_NAME to finish..."
echo "(Ctrl+C is safe: the job keeps running, but its logs are not saved nor the job deleted)"
ELAPSED=0
RESULT=""
while [ "$ELAPSED" -lt "$WAIT_TIMEOUT" ]; do
  SUCCEEDED="$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')"
  FAILED="$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.failed}')"
  if [ "${SUCCEEDED:-0}" -gt 0 ]; then RESULT=succeeded; break; fi
  if [ "${FAILED:-0}" -gt 0 ]; then RESULT=failed; break; fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

EXIT_CODE="$(kubectl get pod -n "$NAMESPACE" -l job-name="$JOB_NAME" \
  -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || true)"

case "$RESULT" in
  succeeded) echo "Job $JOB_NAME finished: all requests returned 2xx." ;;
  failed) echo "Job $JOB_NAME finished with k6 exit code ${EXIT_CODE:-?} (99 = threshold failed, some requests were not 2xx)." ;;
  *)
    echo "Job $JOB_NAME is still running after ${WAIT_TIMEOUT}s, so it was kept. When it finishes:"
    echo "  kubectl logs -n $NAMESPACE job/$JOB_NAME > $DIR/$JOB_NAME.log"
    echo "  kubectl delete job $JOB_NAME -n $NAMESPACE"
    exit 1
    ;;
esac

LOG_FILE="$DIR/$JOB_NAME-$(date +%Y%m%d-%H%M).log"
echo "Saving logs to $LOG_FILE..."
# only delete the job once its logs are safely on disk
if kubectl logs -n "$NAMESPACE" job/"$JOB_NAME" > "$LOG_FILE" && [ -s "$LOG_FILE" ]; then
  echo "Saved $(grep -c '^{' "$LOG_FILE" || true) request lines."
  echo "Deleting job $JOB_NAME..."
  kubectl delete job "$JOB_NAME" -n "$NAMESPACE"
else
  echo "Could not save the logs, so job $JOB_NAME was kept (deleted automatically 24h after it finished)." >&2
  exit 1
fi
