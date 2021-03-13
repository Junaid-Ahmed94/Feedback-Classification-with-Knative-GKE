#!/usr/bin/env bash

# Check for required env vars
if [[ -z "$ISTIO_IP_ADDRESS" ]]; then
  echo "ISTIO_IP_ADDRESS env var must be set. Exiting."
  exit 0
fi
if [[ -z "${1}" ]]; then
  echo "Parameter 1 must be set (to the feedback to leave). Don't forget quotes! Exiting."
  exit 0
fi

FEEDBACK_CONTENT=$1

# (https://superuser.com/questions/272265/getting-curl-to-output-http-status-code)

echo 'Expect 201:'
curl -XPOST -s -o /dev/null -w "%{http_code}" -H 'Content-Type: application/json' -H 'Host: trigger-func.default.example.com' -d "{\"feedback\":\"${FEEDBACK_CONTENT}\"}" $ISTIO_IP_ADDRESS
echo ''
