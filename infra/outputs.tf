output "input_bucket_name" {
  description = "Name of the input bucket for raw documents"
  value       = google_storage_bucket.input_bucket.name
}

output "output_bucket_name" {
  description = "Name of the output bucket for processed results"
  value       = google_storage_bucket.output_bucket.name
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.data_lake.dataset_id
}

output "bigquery_table_id" {
  description = "BigQuery table ID"
  value       = google_bigquery_table.finance_docs.table_id
}

output "document_ai_processor_id" {
  description = "Document AI processor ID"
  value       = google_document_ai_processor.form_parser.id
}

output "dispatcher_function_url" {
  description = "URL of the dispatcher Cloud Function"
  value       = google_cloudfunctions2_function.dispatcher.service_config[0].uri
}

output "loader_function_url" {
  description = "URL of the loader Cloud Function"
  value       = google_cloudfunctions2_function.loader.service_config[0].uri
}

output "service_account_email" {
  description = "Service account email for the pipeline"
  value       = google_service_account.pipeline_sa.email
}
