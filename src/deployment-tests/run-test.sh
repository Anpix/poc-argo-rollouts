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

echo "Creating job $JOB_NAME to run..."
sed \
  -e "s#\$JOB_NAME#$JOB_NAME#g" \
  -e "s#\$TEST_URL#$TEST_URL#g" \
  -e "s#\$TIMEOUT#$TIMEOUT#g" \
  -e "s#\$RATE#$RATE#g" \
  -e "s#\$DURATION#$DURATION#g" \
  src/deployment-tests/test-TEMPLATE.yaml | \
kubectl apply -n deployment-tests -f -

# only handles a single unit (e.g. "30s" or "2m"), not combined ones like "1m30s"
case "$DURATION" in
  *m) DURATION_SECONDS=$(( $(echo "$DURATION" | sed 's/m$//') * 60 )) ;;
  *s) DURATION_SECONDS=$(echo "$DURATION" | sed 's/s$//') ;;
  *) DURATION_SECONDS=30 ;;
esac
WAIT_TIMEOUT=$((DURATION_SECONDS + 60))

echo "Waiting up to ${WAIT_TIMEOUT}s for job $JOB_NAME to finish..."
kubectl wait --for=condition=complete --timeout="${WAIT_TIMEOUT}s" job/"$JOB_NAME" -n deployment-tests \
  || echo "Job $JOB_NAME did not complete successfully — check the log file for details."

echo "Cleaning up the job $JOB_NAME..."
kubectl delete job "$JOB_NAME" -n deployment-tests --ignore-not-found
