provider "google" {
  project = var.project_id
  region  = var.region
}

# ==========================================
# 1. Enable Required APIs
# ==========================================
resource "google_project_service" "enabled_apis" {
  for_each = toset([
    "documentai.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# ==========================================
# 2. Storage Buckets
# ==========================================
resource "google_storage_bucket" "input_bucket" {
  name          = "${var.project_id}-raw-input"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "output_bucket" {
  name          = "${var.project_id}-processed-output"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "functions_bucket" {
  name          = "${var.project_id}-gcf-source"
  location      = var.region
  uniform_bucket_level_access = true
}

# ==========================================
# 3. BigQuery (Schema Evolution Support)
# ==========================================
resource "google_bigquery_dataset" "data_lake" {
  dataset_id = "data_lake"
  location   = var.region
}

resource "google_bigquery_table" "finance_docs" {
  dataset_id = google_bigquery_dataset.data_lake.dataset_id
  table_id   = "finance_docs"

  # Note the JSON type for raw_data
  schema = <<EOF
[
  {
    "name": "file_name",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "processed_timestamp",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "defaultValueExpression": "CURRENT_TIMESTAMP()"
  },
  {
    "name": "invoice_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "total_amount",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "vendor_name",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "confidence_score",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "raw_data",
    "type": "JSON",
    "mode": "NULLABLE"
  }
]
EOF
}

# ==========================================
# 4. Document AI Processor
# ==========================================
resource "google_document_ai_processor" "form_parser" {
  location     = "us" # DocAI usually requires multi-region 'us' or 'eu'
  display_name = "finance-form-parser"
  type         = "FORM_PARSER_PROCESSOR"
}

# ==========================================
# 5. IAM & Service Account
# ==========================================
resource "google_service_account" "pipeline_sa" {
  account_id   = "docai-pipeline-sa"
  display_name = "Document AI Pipeline Service Account"
}

# Grant Permissions to the Service Account
resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",       # Read/Write to buckets
    "roles/documentai.apiUser",        # Call DocAI
    "roles/bigquery.dataEditor",       # Write to BQ
    "roles/logging.logWriter",         # Write logs
    "roles/eventarc.eventReceiver",    # Receive Events
    "roles/run.invoker"                # Invoke Cloud Run (Gen2 functions)
  ])
  role    = each.key
  member  = "serviceAccount:${google_service_account.pipeline_sa.email}"
  project = var.project_id
}

# Grant the storage service agent permission to publish pubsub (needed for Eventarc)
data "google_storage_project_service_account" "gcs_account" {}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# ==========================================
# 6. Cloud Functions (Gen 2)
# ==========================================

# --- Zipping Source Code ---
data "archive_file" "dispatcher_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dispatcher"
  output_path = "${path.module}/files/dispatcher.zip"
}

data "archive_file" "loader_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/loader"
  output_path = "${path.module}/files/loader.zip"
}

# --- Upload Zips to GCS ---
resource "google_storage_bucket_object" "dispatcher_zip" {
  name   = "dispatcher-${data.archive_file.dispatcher_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.dispatcher_zip.output_path
}

resource "google_storage_bucket_object" "loader_zip" {
  name   = "loader-${data.archive_file.loader_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.loader_zip.output_path
}

# --- Function A: Dispatcher ---
resource "google_cloudfunctions2_function" "dispatcher" {
  name        = "docai-dispatcher"
  location    = var.region
  description = "Triggers Batch DocAI Job"

  build_config {
    runtime     = "python310"
    entry_point = "submit_batch_job"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_bucket.name
        object = google_storage_bucket_object.dispatcher_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    available_memory   = "512Mi"
    timeout_seconds    = 60
    service_account_email = google_service_account.pipeline_sa.email
    environment_variables = {
      PROJECT_ID    = var.project_id
      LOCATION      = var.region
      PROCESSOR_ID  = google_document_ai_processor.form_parser.id
      OUTPUT_BUCKET = "gs://${google_storage_bucket.output_bucket.name}"
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.pipeline_sa.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.input_bucket.name
    }
  }
}

# --- Function B: Loader ---
resource "google_cloudfunctions2_function" "loader" {
  name        = "bq-loader"
  location    = var.region
  description = "Loads JSON to BigQuery"

  build_config {
    runtime     = "python310"
    entry_point = "load_to_bq"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_bucket.name
        object = google_storage_bucket_object.loader_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    available_memory   = "512Mi"
    timeout_seconds    = 60
    service_account_email = google_service_account.pipeline_sa.email
    environment_variables = {
      PROJECT_ID = var.project_id
      DATASET_ID = google_bigquery_dataset.data_lake.dataset_id
      TABLE_ID   = google_bigquery_table.finance_docs.table_id
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.pipeline_sa.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.output_bucket.name
    }
  }
}
