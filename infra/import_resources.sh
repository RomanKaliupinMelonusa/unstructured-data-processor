#!/bin/bash

# This script imports existing GCP resources into the Terraform state.
# Run this script locally after authenticating with gcloud:
# gcloud auth application-default login

PROJECT_ID="unstructured-data-processor"

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed."
    echo "Please install it using: brew install terraform"
    exit 1
fi

echo "Initializing Terraform..."
terraform init

echo "Importing Input Bucket..."
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_storage_bucket.input_bucket $PROJECT_ID-raw-input

echo "Importing Output Bucket..."
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_storage_bucket.output_bucket $PROJECT_ID-processed-output

echo "Importing Functions Bucket..."
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_storage_bucket.functions_bucket $PROJECT_ID-gcf-source

echo "Importing BigQuery Dataset..."
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_bigquery_dataset.data_lake projects/$PROJECT_ID/datasets/data_lake

echo "Importing Service Account..."
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_service_account.pipeline_sa projects/$PROJECT_ID/serviceAccounts/docai-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com

echo "Importing Cloud Functions (if they exist)..."
# Attempt to import functions, ignore failure if they don't exist or if import fails (user can verify manually)
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_cloudfunctions2_function.dispatcher projects/$PROJECT_ID/locations/us-central1/functions/docai-dispatcher || true
terraform import -var="project_id=$PROJECT_ID" -var="region=us-central1" google_cloudfunctions2_function.loader projects/$PROJECT_ID/locations/us-central1/functions/bq-loader || true

echo "Import complete. Run 'terraform plan' to verify."
