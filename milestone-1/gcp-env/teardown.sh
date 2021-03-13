#!/usr/bin/env bash

PROJECT_ID=$(gcloud config get-value project)

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Must run gcloud init first. Exiting."
  exit 0
fi

# These env vars must match the ones used in setup.sh.
ZONE="europe-west3-a"
CONTROL_PLANE_NAME="knative-gcp-control-plane"

echo "Beginning env teardown."

# Delete k8s cluster
gcloud container clusters delete classify-events --zone $ZONE --quiet

# Delete Pub/Sub topics
# (https://cloud.google.com/sdk/gcloud/reference/pubsub/topics/delete)
gcloud pubsub topics delete feedback-created feedback-classified

# Delete Google service accounts
 gcloud iam service-accounts delete "$CONTROL_PLANE_NAME@$PROJECT_ID.iam.gserviceaccount.com" --quiet

