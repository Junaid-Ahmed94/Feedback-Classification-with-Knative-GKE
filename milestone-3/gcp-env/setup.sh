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

# App Engine
gcloud app create --region ${REGION}
gcloud firestore databases create --region ${REGION}

# Create k8s cluster
CLUSTER_NAME="classify-events"
MACHINE_TYPE="e2-standard-2"
CLUSTER_VERSION="1.18.16-gke.302"
REGION="europe-west3"
ZONE="europe-west3-a"
gcloud beta container --project "$PROJECT_ID" clusters create $CLUSTER_NAME \
  --zone $ZONE --no-enable-basic-auth  \
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
  # --cluster-version $CLUSTER_VERSION

# Install Knative onto newly-created cluster.
KNATIVE_SERVING_VERSION="v0.19.0"
KNATIVE_EVENTING_VERSION="v0.19.0"
kubectl apply --filename https://github.com/knative/serving/releases/download/$KNATIVE_SERVING_VERSION/serving-crds.yaml
kubectl apply --filename https://github.com/knative/serving/releases/download/$KNATIVE_SERVING_VERSION/serving-core.yaml
kubectl apply --filename https://github.com/knative/net-istio/releases/download/$KNATIVE_SERVING_VERSION/release.yaml
kubectl apply --filename https://github.com/knative/eventing/releases/download/$KNATIVE_EVENTING_VERSION/eventing-crds.yaml
kubectl apply --filename https://github.com/knative/eventing/releases/download/$KNATIVE_EVENTING_VERSION/eventing-core.yaml

# Install knative-gcp CRDs)
KGCP_VERSION=v0.19.0
kubectl apply --filename https://github.com/google/knative-gcp/releases/download/${KGCP_VERSION}/cloud-run-events-pre-install-jobs.yaml
kubectl apply --selector events.cloud.google.com/crd-install=true \
--filename https://github.com/google/knative-gcp/releases/download/${KGCP_VERSION}/cloud-run-events.yaml
kubectl apply --filename https://github.com/google/knative-gcp/releases/download/${KGCP_VERSION}/cloud-run-events.yaml

# Create Google Service Account (GSA) required for knative-gcp control plane
# and give it enough permissions to create, delete, attach, and detach
# subscriptions (needed for CloudPubSubSource from knative-gcp).
CONTROL_PLANE_NAME="knative-gcp-control-plane"
CONTROL_PLANE_GSA="$CONTROL_PLANE_NAME@$PROJECT_ID.iam.gserviceaccount.com"
gcloud iam service-accounts create $CONTROL_PLANE_NAME
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CONTROL_PLANE_GSA" \
  --role="roles/pubsub.editor"

# Link the control plane GSA to the control plane Kubernetes Service Account
# (KSA) that knative-gcp automatically created in the cluster in the previous
# steps.

# 1/2 Linking - Tell Google that the KSA is allowed to impersonate the GSA.
# Note that knative-gcp uses the namespace "cloud-run-events" in the cluster.
KNATIVE_GCP_NAMESPACE="cloud-run-events"
CONTROL_PLANE_KSA="controller"
gcloud iam service-accounts add-iam-policy-binding  \
  --member "serviceAccount:$PROJECT_ID.svc.id.goog[$KNATIVE_GCP_NAMESPACE/$CONTROL_PLANE_KSA]" \
  --role roles/iam.workloadIdentityUser \
  "$CONTROL_PLANE_GSA"

# 2/2 Linking - Tell the KSA that it can impersonate the GSA.
kubectl annotate serviceaccount --namespace $KNATIVE_GCP_NAMESPACE $CONTROL_PLANE_KSA \
  "iam.gke.io/gcp-service-account=$CONTROL_PLANE_GSA" --overwrite

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
