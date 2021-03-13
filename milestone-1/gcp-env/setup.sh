#!/usr/bin/env bash

PROJECT_ID=$(gcloud config get-value project)

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Must run gcloud init first. Exiting."
  exit 0
fi

REGION="europe-west"
ZONE="europe-west3-a"

echo "Beginning env setup."

gcloud services enable --project $PROJECT_ID \
  cloudbuild.googleapis.com \
  appengine.googleapis.com \
  language.googleapis.com \
  sheets.googleapis.com \
  container.googleapis.com

echo "Enabled required Google APIs."

# App Engine is a requirement for using Firestore.
# App Engine refers to the region as "us-central" right now.
gcloud app create --region ${REGION}
gcloud firestore databases create --region ${REGION}

# Create k8s cluster
# Command obtained using the "Equivalent command line" option in UI, using
# default settings except:
#  - Changed version to Regular release channel
#  - Enabled Istio under Features
#  - Enabled Workload Identity under Security
CLUSTER_NAME="classify-events"
MACHINE_TYPE="e2-standard-2"
CLUSTER_VERSION="1.18.12-gke.1210"
REGION="europe-west3"
ZONE="europe-west3-a"
gcloud beta container --project "$PROJECT_ID" clusters create $CLUSTER_NAME \
  --zone $ZONE --no-enable-basic-auth --cluster-version $CLUSTER_VERSION \
  --release-channel "regular" --machine-type $MACHINE_TYPE --image-type "COS" \
  --disk-type "pd-standard" --disk-size "100" --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --num-nodes "3" --enable-stackdriver-kubernetes --enable-ip-alias \
  --network "projects/$PROJECT_ID/global/networks/default" \
  --subnetwork "projects/$PROJECT_ID/regions/$REGION/subnetworks/default" \
  --default-max-pods-per-node "110" --no-enable-master-authorized-networks \
  --addons HorizontalPodAutoscaling,HttpLoadBalancing,Istio \
  --istio-config auth=MTLS_PERMISSIVE --enable-autoupgrade --enable-autorepair \
  --max-surge-upgrade 1 --max-unavailable-upgrade 0 \
  --workload-pool "$PROJECT_ID.svc.id.goog"

# Install Knative onto newly-created cluster.
# (https://knative.dev/docs/install/any-kubernetes-cluster/#installing-the-serving-component)
KNATIVE_SERVING_VERSION="v0.19.0"
KNATIVE_EVENTING_VERSION="v0.19.0"
kubectl apply --filename https://github.com/knative/serving/releases/download/$KNATIVE_SERVING_VERSION/serving-crds.yaml
kubectl apply --filename https://github.com/knative/serving/releases/download/$KNATIVE_SERVING_VERSION/serving-core.yaml
kubectl apply --filename https://github.com/knative/net-istio/releases/download/$KNATIVE_SERVING_VERSION/release.yaml

echo "Waiting 15 seconds for GCP to provision external load balancer for Istio..."
sleep 15

echo
echo "*** Use the following external IP for sending requests to your apps: ***"
kubectl --namespace istio-system get service istio-ingressgateway

# Create Pub/Sub topics
# (https://cloud.google.com/sdk/gcloud/reference/pubsub/topics/create)
gcloud pubsub topics create feedback-created
gcloud pubsub topics create feedback-classified

echo "Optionally, use the test_kn_deployment.yaml script to deploy a sample from Knative docs to make sure the cluster is working."
