terraform {
  backend "gcs" {
    bucket = "unstructured-data-processor-terraform-state"
    prefix = "terraform/state"
  }
}
