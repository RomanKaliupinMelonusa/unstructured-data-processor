import os
from google.cloud import documentai_v1 as documentai

PROJECT_ID = os.environ.get("PROJECT_ID")
LOCATION = os.environ.get("LOCATION", "us-central1")
PROCESSOR_ID = os.environ.get("PROCESSOR_ID")
OUTPUT_BUCKET = os.environ.get("OUTPUT_BUCKET")

def submit_batch_job(cloud_event):
    data = cloud_event.data
    input_bucket = data["bucket"]
    file_name = data["name"]
    mime_type = data.get("contentType", "application/pdf")

    # Validate inputs (Simple filter)
    if not (mime_type == "application/pdf" or "image" in mime_type):
        print(f"Skipping non-doc file: {file_name}")
        return

    client = documentai.DocumentProcessorServiceClient(
        client_options={"api_endpoint": f"{LOCATION}-documentai.googleapis.com"}
    )

    # The resource name of the processor
    name = client.processor_path(PROJECT_ID, LOCATION, PROCESSOR_ID)

    # Configure Input (Source)
    gcs_uri = f"gs://{input_bucket}/{file_name}"
    gcs_source = documentai.GcsSource(uri=gcs_uri)
    input_config = documentai.BatchDocumentsInputConfig(
        gcs_documents=documentai.GcsDocuments(documents=[{"gcs_uri": gcs_uri, "mime_type": mime_type}])
    )

    # Configure Output (Destination)
    # Document AI creates a folder inside this bucket for the results
    gcs_output_config = documentai.DocumentOutputConfig(
        gcs_output_config={"gcs_uri": f"{OUTPUT_BUCKET}/{file_name}_results/"}
    )

    # Configure Request
    request = documentai.BatchProcessRequest(
        name=name,
        input_documents=input_config,
        document_output_config=gcs_output_config,
        skip_human_review=False # Set to False to enable HITL if configured in Console
    )

    # Submit the Operation
    operation = client.batch_process_documents(request=request)
    print(f"Batch operation started for {file_name}. Operation ID: {operation.operation.name}")
    # We do NOT wait for the result here. The Function ends successfully.
