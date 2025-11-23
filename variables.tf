variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region for Compute resources"
  type        = string
  default     = "us-central1"
}
