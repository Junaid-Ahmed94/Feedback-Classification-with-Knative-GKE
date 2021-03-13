#!/usr/bin/env bash

PROJECT_ID=$(gcloud config get-value project)

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Must run gcloud init first. Exiting."
  exit 0
fi

APP_NAME="trigger-func"
TOPIC_NAME="feedback-created"

# Create service accounts for app before deploying if neccessary.
# (https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#authenticating_to)

# First, create Kubernetes (k8s) service account (SA).
kubectl create serviceaccount $APP_NAME

#  Then, create Google service account (which the k8s SA will act as).
gcloud iam service-accounts create $APP_NAME

GOOGLE_SERVICE_ACCOUNT="$APP_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# Add the permissions (Firestore and Pub/Sub) that the app needs to the Google
# service account:

# Firestore is called "datastore" in IAM right now, and the most granular level
# you can apply permissions to right now is the entire GCP project containing
# the Firestore database. Therefore, we give the service account permission to
# read and write any document in any Firestore collection.
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member "serviceAccount:$GOOGLE_SERVICE_ACCOUNT" \
  --role roles/datastore.user

# Pub/Sub is one of the GCP products that lets you set permissions at a more
# granular level than to the entire project. Therefore, we give the service
# account permission to publish to the topic.
gcloud pubsub topics add-iam-policy-binding $TOPIC_NAME \
  --member "serviceAccount:$GOOGLE_SERVICE_ACCOUNT" \
  --role roles/pubsub.publisher

# Then, tell Google that the k8s SA is allowed to impersonate the Google SA.
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:$PROJECT_ID.svc.id.goog[default/$APP_NAME]" \
  $GOOGLE_SERVICE_ACCOUNT

# Then, tell the k8s SA that it can impersonate the Google SA.
kubectl annotate serviceaccount \
  $APP_NAME \
  iam.gke.io/gcp-service-account=$GOOGLE_SERVICE_ACCOUNT \
  --overwrite

# Build image via Cloud Build
# Knative requires a change to have been made to the service YAML file for it
# to create a new revision. Therefore, we use a unique value for the image tag
# for each build. A Git commit hash is a good choice for this, but because this
# script may be run from outside of a Git repo, we use a random string.
# credit: https://gist.github.com/earthgecko/3089509
VERSION=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1)
TAG="gcr.io/$PROJECT_ID/$APP_NAME:$VERSION"
gcloud builds submit --tag $TAG

# Fill in service.yaml template with project-specific info and then use it to
# deploy. Forward slashes in image name are escaped using backslashes.
cat service.template.yaml \
  | sed "s/{{IMAGE}}/gcr.io\/$PROJECT_ID\/$APP_NAME:$VERSION/g" \
  > service.yaml
kn service apply -f service.yaml
